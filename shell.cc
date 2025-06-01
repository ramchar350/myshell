#include <cstdio>

#include "shell.hh"
#include <unistd.h>

#include <signal.h>
#include <string.h>
#include <sys/wait.h>

int yyparse(void);

// Initialize the debug flag
bool Shell::_debug = false;

// Variable to track if a command is currently running
static int commandRunning = 0;

// Signal handler for Ctrl-C
extern "C" void sigintHandler(int sig) {
  // If no command is running, print a new prompt
  if(!commandRunning) {
    printf("\n");
    Shell::prompt();
    fflush(stdout);
  }
}

// Signal handler for SIGCHLD
extern "C" void sigchldHandler(int sig) {
  int status;
  pid_t pid;

  // Use non-blocking waitpid to reap all zombie children
  while ((pid = waitpid(-1, &status, WNOHANG)) > 0) {
    // Only print message for background processes that have been completed
    //printf("[%d] exited.\n", pid);
    //fflush(stdout);
  }
}

void Shell::prompt() {
  // Only print prompt if stdin is a terminal
  if (isatty(0)) {
    printf("myshell>");
    fflush(stdout);
  }
}

// Function to set up signal handling
void setupSignalHandling() {
  struct sigaction sa;

  // Set up for SIGINT handler
  sa.sa_handler = sigintHandler;
  sigemptyset(&sa.sa_mask);
  sa.sa_flags = SA_RESTART;

  if (sigaction(SIGINT, &sa, NULL)) {
    perror("sigaction for SIGINT");
    exit(2);
  }

  // Set up for SIGCHLD handler
  sa.sa_handler = sigchldHandler;
  sigemptyset(&sa.sa_mask);
  sa.sa_flags = SA_RESTART;

  if (sigaction(SIGCHLD, &sa, NULL)) {
    perror("sigaction for SIGCHLD");
    exit(2);
  }
}


// Function to call before executing a command
void startCommand() {
  commandRunning = 1;
}


// Function to call after a command completes
void endCommand() {
  commandRunning = 0;
}

int main() {

  setupSignalHandling();

  // Only prompt if stdin is a terminal
  if (isatty(0)) {
    Shell::prompt();
  }
  yyparse();
}

Command Shell::_currentCommand;
