#include <stdio.h>

#include <string.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>

#include <pthread.h>

#include "lacweb.h"

int lw_port = 8080;
int lw_backlog = 10;
int lw_bufsize = 1024;

void lw_handle(lw_context, char*);

typedef struct node {
  int fd;
  struct node *next;
} *node;

static node front = NULL, back = NULL;

static int empty() {
  return front == NULL;
}

static void enqueue(int fd) {
  node n = malloc(sizeof(struct node));

  n->fd = fd;
  n->next = NULL;
  if (back)
    back->next = n;
  else
    front = n;
  back = n;
}

static int dequeue() {
  int ret = front->fd;

  front = front->next;
  if (!front)
    back = NULL;

  return ret;
}

static pthread_mutex_t queue_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t queue_cond = PTHREAD_COND_INITIALIZER;

static void *worker(void *data) {
  int me = *(int *)data;
  lw_context ctx = lw_init(1024, 1024);

  while (1) {
    char buf[lw_bufsize+1], *back = buf, *s;
    int sock;

    pthread_mutex_lock(&queue_mutex);
    while (empty())
      pthread_cond_wait(&queue_cond, &queue_mutex);
    sock = dequeue();
    pthread_mutex_unlock(&queue_mutex);

    printf("Handling connection with thread #%d.\n", me);

    while (1) {
      int r = recv(sock, back, lw_bufsize - (back - buf), 0);

      if (r < 0) {
        fprintf(stderr, "Recv failed\n");
        break;
      }

      if (r == 0) {
        printf("Connection closed.\n");
        break;
      }

      printf("Received %d bytes.\n", r);

      back += r;
      *back = 0;
    
      if (s = strstr(buf, "\r\n\r\n")) {
        char *cmd, *path;

        *s = 0;
      
        if (!(s = strstr(buf, "\r\n"))) {
          fprintf(stderr, "No newline in buf\n");
          break;
        }

        *s = 0;
        cmd = s = buf;
      
        if (!strsep(&s, " ")) {
          fprintf(stderr, "No first space in HTTP command\n");
          break;
        }

        if (strcmp(cmd, "GET")) {
          fprintf(stderr, "Not ready for non-get command: %s\n", cmd);
          break;
        }

        path = s;
        if (!strsep(&s, " ")) {
          fprintf(stderr, "No second space in HTTP command\n");
          break;
        }

        printf("Serving URI %s....\n", path);

        ctx = lw_init(1024, 1024);
        lw_write (ctx, "HTTP/1.1 200 OK\r\n");
        lw_write(ctx, "Content-type: text/html\r\n\r\n");
        lw_write(ctx, "<html>");
        lw_handle(ctx, path);
        lw_write(ctx, "</html>");

        lw_send(ctx, sock);

        printf("Done with client.\n\n");
        break;
      }
    }

    close(sock);
    lw_reset(ctx);
  }
}

int main(int argc, char *argv[]) {
  // The skeleton for this function comes from Beej's sockets tutorial.
  int sockfd;  // listen on sock_fd
  struct sockaddr_in my_addr;
  struct sockaddr_in their_addr; // connector's address information
  int sin_size, yes = 1;
  int nthreads, i, *names;

  if (argc < 2) {
    fprintf(stderr, "No thread count specified\n");
    return 1;
  }

  nthreads = atoi(argv[1]);
  if (nthreads <= 0) {
    fprintf(stderr, "Invalid thread count\n");
    return 1;
  }
  names = calloc(nthreads, sizeof(int));

  sockfd = socket(PF_INET, SOCK_STREAM, 0); // do some error checking!

  if (sockfd < 0) {
    fprintf(stderr, "Listener socket creation failed\n");
    return 1;
  }

  if (setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(int)) < 0) {
    fprintf(stderr, "Listener socket option setting failed\n");
    return 1;
  }

  my_addr.sin_family = AF_INET;         // host byte order
  my_addr.sin_port = htons(lw_port);    // short, network byte order
  my_addr.sin_addr.s_addr = INADDR_ANY; // auto-fill with my IP
  memset(my_addr.sin_zero, '\0', sizeof my_addr.sin_zero);

  if (bind(sockfd, (struct sockaddr *)&my_addr, sizeof my_addr) < 0) {
    fprintf(stderr, "Listener socket bind failed\n");
    return 1;
  }

  if (listen(sockfd, lw_backlog) < 0) {
    fprintf(stderr, "Socket listen failed\n");
    return 1;
  }

  sin_size = sizeof their_addr;

  printf("Listening on port %d....\n", lw_port);

  for (i = 0; i < nthreads; ++i) {
    pthread_t thread;    
    names[i] = i;
    if (pthread_create(&thread, NULL, worker, &names[i])) {
      fprintf(stderr, "Error creating worker thread #%d\n", i);
      return 1;
    }
  }

  while (1) {
    int new_fd = accept(sockfd, (struct sockaddr *)&their_addr, &sin_size);

    if (new_fd < 0) {
      fprintf(stderr, "Socket accept failed\n");
      return 1;
    }

    printf("Accepted connection.\n");

    pthread_mutex_lock(&queue_mutex);
    enqueue(new_fd);
    pthread_cond_broadcast(&queue_cond);
    pthread_mutex_unlock(&queue_mutex);
  }
}
