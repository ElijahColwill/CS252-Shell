#include <cstdio>
#include <cstdlib>

#include <iostream>
#include <unistd.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <cstring>

#include "command.hh"
#include "shell.hh"


// Prototypes for imported functions
int yyparse(void);
int source_cmd(const char * filename);

// Initialize global environ array and _lastArgument string
extern char ** environ;
std::string _lastArgument;

Command::Command() {
    // Initialize a new vector of Simple Commands
    _simpleCommands = std::vector<SimpleCommand *>();
 
    // Initialize variables to hold file redirection destinatiosn
    _outFile = NULL;
    _inFile = NULL;
    _errFile = NULL;

    // Initiatize booleans to track background process status and append preference
    _background = false;
    _append = false;
 
}

void Command::insertSimpleCommand( SimpleCommand * simpleCommand ) {
    // Add the simple command to the vector
    _simpleCommands.push_back(simpleCommand);
}


// Return last argument passed by this command
std::string Command::getLastArgument() {
    return _lastArgument;
}

void Command::clear() {
    // Deallocate all the simple commands in the command vector
    for (auto & simpleCommand : _simpleCommands) {
        delete simpleCommand;
    }

    // Remove all references to the simple commands we've deallocated
    // (basically just sets the size to 0)
    _simpleCommands.clear();

    // Handle possible double free errors by checking for multiple
    // redirects to the same file.
    if (_inFile == _errFile || _outFile == _errFile) {_errFile = NULL;}
    if (_outFile == _inFile) {_inFile = NULL;}

    // Deallocate file redirect variables.
    if ( _outFile ) {
        delete _outFile;
    }
    _outFile = NULL;

    if ( _inFile ) {
        delete _inFile;
    }
    _inFile = NULL;

    if ( _errFile ) {
        delete _errFile;
    }
    _errFile = NULL;

    // Set boolean values back to default (1)
    _background = false;
    _append = false;
}

void Command::print() {
    printf("\n\n");
    printf("              COMMAND TABLE                \n");
    printf("\n");
    printf("  #   Simple Commands\n");
    printf("  --- ----------------------------------------------------------\n");

    int i = 0;
    // iterate over the simple commands and print them nicely
    for ( auto & simpleCommand : _simpleCommands ) {
        printf("  %-3d ", i++ );
        simpleCommand->print();
    }

    printf( "\n\n" );
    printf( "  Output       Input        Error        Background\n" );
    printf( "  ------------ ------------ ------------ ------------\n" );
    printf( "  %-12s %-12s %-12s %-12s\n",
            _outFile?_outFile->c_str():"default",
            _inFile?_inFile->c_str():"default",
            _errFile?_errFile->c_str():"default",
            _background?"YES":"NO");
    printf( "\n\n" );
}

void Command::execute() {
    // Base Case: Prompt and return if there are no simple commands
    if ( _simpleCommands.size() == 0 ) {
        Shell::prompt();
        return;
    }
 
    // Initialize command name variable to check for special commands
    const char * cmd = _simpleCommands[0]->_arguments[0]->c_str();

    // Base Case: Exit with goodbye message if exit command passed.
    if ( strcmp(cmd, "exit") == 0 ) {
       printf("Good Bye!!\n");
       clear();
       exit(0);
    }
 
    // Initialize process ID variable
    int ret = 0;

    // Initialize default stdin/stdout/stderr file descriptors
    int default_in = dup(0);
    int default_out = dup(1);
    int default_err = dup(2);

    // Initialize command file descriptors
    int fdin;
    int fdout;
    int fderr;

    // Set initial fdin value based on input file
    if (_inFile) {fdin = open(_inFile->c_str(), O_RDONLY);}
    else {fdin = dup(default_in);}

    // Set initial fderr value based one error fiel
    if (_errFile && _append) {fderr = open(_errFile->c_str(), O_WRONLY | O_CREAT | O_APPEND , 0600);}
    else if (_errFile) {fderr = open(_errFile->c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0600);}
    else {fderr = dup(default_err);}

    // Direct fderr descriptor to stderr and close
    dup2(fderr, 2);
    close(fderr);

    // Loop through and execute each simple command from given command
    for (size_t i = 0; i < _simpleCommands.size(); i++) {

	// Direct fdin descriptor to stdin and close
	dup2(fdin, 0);
	close(fdin);

	// Set _lastArgument command to the last element in the _arguments vector for
	// current simple command.
	_lastArgument = std::string(*_simpleCommands[i]->_arguments.back());

	// If at the last simple command, direct final output to _outFile
	// Otherwise, set up and initialize pipe to pass output forward
        if (i == _simpleCommands.size() - 1) {
	   if (_outFile && _append) {fdout = open(_outFile->c_str(), O_WRONLY | O_CREAT | O_APPEND, 0600);}
	   else if (_outFile) {fdout = open(_outFile->c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0600);}
	   else {fdout = dup(default_out);}
	} else {
	   int fdpipe[2];
	   if (pipe(fdpipe) == -1) {
	      perror("pipe");
	      exit(2);
	   }
	   fdout = fdpipe[1];
	   fdin = fdpipe[0];
	}

	// Direct fdout descriptor to stdout and close
	dup2(fdout, 1);
	close(fdout);

	// Update cmd variable to current simple command name
        cmd = _simpleCommands[i]->_arguments[0]->c_str();

        // EXECUTING COMMANDS: During either built-in or child process execution,
	// return status will be updated for reference in built-in environmental 
	// variables and the shell.

	// Change Directory Command: Defaults to home directory if no
	// arguments passed, throws error if directory not found.
        if ( strcmp(cmd, "cd") == 0 ) {
            int error;
	    if (_simpleCommands[i]->_arguments.size() == 1) {
              error = chdir(getenv("HOME"));
            } else {
              error = chdir(_simpleCommands[i]->_arguments[1]->c_str());
            }
            if (error == -1) {
              fprintf(stderr, "cd: can't cd to %s\n", _simpleCommands[i]->_arguments[1]->c_str());
	      if (!_background) Shell::_returnStatus = 1;
	    } else {if (!_background) Shell::_returnStatus = 0;}
	// Set Environment Variable Command: Stays in parent process, throws
	// error if three arguemnts not given, utilizes setenv().
        } else if ( strcmp(cmd, "setenv") == 0 ) {
	     if (_simpleCommands[i]->_arguments.size() != 3) {
	        fprintf(stderr, "setenv requires three arguments\n");
                if (!_background) Shell::_returnStatus = 1;
	     } else {
		const char * A = _simpleCommands[i]->_arguments[1]->c_str();
                const char * B = _simpleCommands[i]->_arguments[2]->c_str();
                int error = setenv(A, B, 1);
		if (!_background) Shell::_returnStatus = error;
	     }
	// Unset Environment Variable Command: Removes environment
	// variable, stays in parent process, throws error if two 
	// arguments not given.
        } else if ( strcmp(cmd, "unsetenv") == 0 ) { 
             if (_simpleCommands[i]->_arguments.size() != 2) {
	        fprintf(stderr, "unsetenv requires one argument\n");
                if (!_background) Shell::_returnStatus = 1;
	     } else {
                int error = unsetenv(_simpleCommands[i]->_arguments[1]->c_str());
                if (!_background) Shell::_returnStatus = error;
	     }
	// Source command: calls source command in shell.l to parse given file
	// as input to the shell, with error handling.
        } else if ( strcmp(cmd, "source") == 0 ) {
	    if (_simpleCommands[i]->_arguments.size() != 2) {
	      fprintf(stderr, "source requires two arguments\n");
              if (!_background) Shell::_returnStatus = 1;
	      clear();
	      break;
	    }
	    char * filename = strdup(_simpleCommands[i]->_arguments[1]->c_str());
	    std::vector<SimpleCommand *> _tempCommands = std::vector<SimpleCommand *>();
	    for (auto & sc : _simpleCommands) {
	      delete sc;
	    }
	    _simpleCommands.clear();
	    if (source_cmd(filename) == -1) {
	      fprintf(stderr, "file not found\n");
              if (!_background) Shell::_returnStatus = 1;
	      clear();
	    } else {
	      if (!_background) Shell::_returnStatus = 0;
	    }
            free(filename);
	    for (size_t i = 0; i < _tempCommands.size(); i++) {
	      _simpleCommands.push_back(_tempCommands.at(i));
	    }
            dup2(fdin, 0);
   	    close(fdin);
	// All other commands (not built-in): crate child process and call execvp
	} else {	
          ret = fork();
	  // Child process created
	  if (ret == 0) {
	    // Print Enviroment Variable Command
            if ( strcmp(cmd, "printenv") == 0 ) {
              char ** env = environ;
              while(*env) {
	        printf("%s\n", *env);
                env++;
	      }
	      if (!_background) Shell::_returnStatus = 0;
	      exit(0);
	    // Source Command: Throws error if file not given,
	    // calls source_cmd function found in shell.l
            } else {
	      // Create arrray of arguments compatible with execvp and 
	      // pass in all arguments from current simple command.
	      std::vector<char *> execvp_array = std::vector<char *>();
	      for (unsigned int j = 0; j < _simpleCommands[i]->_arguments.size(); j++) {
	        execvp_array.push_back(const_cast<char *>(_simpleCommands[i]->_arguments[j]->c_str()));
	      }
              
	      // Push NULL argument and call execvp to execute command.
	      execvp_array.push_back(NULL);
	      execvp(execvp_array[0], execvp_array.data());
	  
	      // If execvp does not execute, throw error and exit
	      // NOTE: _exit(1), not exit() used.
	      perror("execvp");
              if (!_background) Shell::_returnStatus = 1;
	      _exit(1);
	    }
	  // If ret is negative, fork did not execute correctly. Throw error.
	  } else if (ret < 0) {
	      perror("fork");
	      if (!_background) Shell::_returnStatus = 2;
	      exit(2);
	  }

	}
    }

    // Direct stdin/stdout/stderr back to defaults.
    dup2(default_in, 0);
    dup2(default_out, 1);
    dup2(default_err, 2);

    // Close temporary file descriptors
    close(default_in);
    close(default_out);
    close(default_err);

    // If process not a background process, wait for child process to complete
    // Otherwise, continue running and add the PID to the background process
    // tracking data structure. Additionally, handle the return status.
    if (!_background) {
       int status;
       waitpid(ret, &status, 0);
       Shell::_returnStatus = WEXITSTATUS(status);
       char * custom_error = getenv("ON_ERROR");
       if (custom_error != NULL && Shell::_returnStatus != 0) printf("%s\n", custom_error);
    } else {
       Shell::_bkgPIDs.push_back(ret);
       Shell::_lastBkgProcess = ret;
    }

    // Print contents of Command data structure
    //print();

    // Clear to prepare for next command
    clear();

    // Print new prompt
    Shell::prompt();
}

SimpleCommand * Command::_currentSimpleCommand;
