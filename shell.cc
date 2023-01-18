#include <cstdio>

#include "shell.hh"
#include "y.tab.hh"
#include <unistd.h>
#include <signal.h>
#include <sys/wait.h>

// Prototypes for imported commands
int yyparse(void);
int source_cmd(const char * filename);
void yyrestart(FILE *);

extern "C" void sigINT (int sig) {
    
    // Handle CTRL-C, and print a prompt if command not already present
    // (if a command was running, it will handle printing the new prompt
    // when execution is stopped)	
    if (sig == SIGINT) {
    	printf("\n");
	if (Shell::_currentCommand._simpleCommands.size() == 0) {
	  Shell::prompt();
	}
	// Clear/deallocate running command.
        Shell::_currentCommand.clear();
    }
    // Handle Zombie Processes, and print the PID of the process
    // that was stopped, checking the PID against the background
    // process tracking data structure.
    if (sig == SIGCHLD) {
	pid_t pid = waitpid(-1, NULL, WNOHANG);
	Shell::process_check(pid);
	while (pid > 0) {
	    pid = waitpid(-1, NULL, WNOHANG);
	    Shell::process_check(pid);
	}
    }
}

void Shell::process_check(pid_t pid) {
   // Iterate through background process tracking data structure
   // and print the passed PID if found, removing it from the
   // data structure.
   for (unsigned int i = 0; i < _bkgPIDs.size(); i++) {
   	if (pid == Shell::_bkgPIDs[i]) {
	   printf("\n[%ld] exited.\n", (long) pid);
	   Shell::prompt();
	   Shell::_bkgPIDs.erase(Shell::_bkgPIDs.begin() + i);
	   break;
	}
   }
}

void Shell::prompt() {
  // Print a prompt to the user if the command did not originate
  // from a source call, and input did not come from a file.
  if (isatty(0) && !_source) {
    char * custom_prompt = getenv("PROMPT");
    if (custom_prompt) printf("%s", custom_prompt);
    else printf("myshell>");
  }
  // Flush stdout buffer.
  fflush(stdout);
}

int main() {
  // Initialize and set up necessary items and flags
  // for sigaction to catch signals.
  struct sigaction sa;
  sa.sa_handler = sigINT;
  sigemptyset(&sa.sa_mask);
  sa.sa_flags = SA_RESTART;

  // Initalize source boolean to default value (1) and
  // other starting variables.
  Shell::_source = false;
  Shell::_returnStatus = -1;
  Shell::_lastBkgProcess = -1;

  // When shell process starts, run source command
  // with set-up file .shellrc
  source_cmd(".shellrc");

  // Catch SIGINT (CTRL-C) signals and handle errors.
  if (sigaction(SIGINT, &sa, NULL)) {
	perror("sigaction-SIGINT");
	exit(2);
  }

  // Catch SIGCHLD (Zomblie) signals and handle errros.
  if (sigaction(SIGCHLD, &sa, NULL)) {
  	perror("sigaction-SIGCHLD");
	exit(2);
  }

  // Print prompt to the user, restart stdin buffer,
  // and call parser.
  Shell::prompt();
  yyrestart(stdin);
  yyparse();
}

Command Shell::_currentCommand;
std::vector<int> Shell::_bkgPIDs;
bool Shell::_source;
int Shell::_returnStatus;
int Shell::_lastBkgProcess;
