
/*
 *
 * CS-252 
 * shell.l: lexical analyzer for shell
 * You have to extend it.
 *
 */

%{

#include <cstring>
#include "y.tab.hh"
#include "shell.hh"
#include <sys/wait.h>
#include <fcntl.h>
#include <unistd.h>

// Extern for reading input into read-line.c
extern "C" char * read_line();

// Custon function to handle any input not from a file through read_line()
int mygetc(FILE * f) {
  static char *p;
  char ch;
  
  if(!isatty(0)) {
    return getc(f);
  }

  if (p == NULL || *p == 0) {
    char * s = read_line();
    p = s;
  }

  ch = *p;
  p++;

  return ch;

}

#undef getc
#define getc(f) mygetc(f)


// Subshell Setup: Functions for passing from buffer
static void yyunput (int c,char *buf_ptr  );

void myunputc(int c) {
  unput(c);
}


// Run source input from a file to shell
int source_cmd(const char * file) {
  // Initialize fp object with r+ permissions from passed file.
  FILE * fp = fopen(file, "r+");  

  // If file does not exist, return error state.
  if (!fp) {return -1;}
  fseek(fp, 0L, SEEK_SET);  

  // Create and push a new buffer with default buffer size to the stack
  yypush_buffer_state(yy_create_buffer(fp, YY_BUF_SIZE));
  // Update source boolean to indicate source input has started.
  Shell::_source = true;
  // Parse source input and pop buffer off of stack when finished.
  yyparse();
  yypop_buffer_state();

  // Close fp object and update shell boolean. Return normal state.
  fclose(fp);
  Shell::_source = false;
  return 0;
}

%}

%option noyywrap

%%

\n {
  return NEWLINE;
}

[ \t] {
  /* Discard spaces and tabs */
}

">" {
  return GREAT;
}

"<" {
  return LESS;	
}

">>" {
  return GREATGREAT;
}

">&" {
  return GREATAMP;
}

">>&" {
  return GREATGREATAMP;
}

"2>" {
  return TWOGREAT;
}

"|" {
  return PIPE;
}

"&" {
  return AMP; 
}

\`[^\n\`]*\`|$\([^\n]*\) {
  // Subshell comamnd
  // Initialize initial buffer size
  int buffer_size = 1024;

  // Create string from input command and remove noise characters ($, (, ), `)
  std::string str = std::string(yytext);
  if (str.at(0) == '$') {
    str = str.substr(1, std::string::npos);
  }
  str = str.substr(1, str.size() - 2);
  // Pass exit command to input string to ensure subshell process exits
  str += "\nexit\n";
  
  // Create default stdin/stdout file descriptors 
  int defaultin = dup(0);
  int defaultout = dup(1);
  
  // Initialze pipes and check for errors
  int pipein[2];
  int pipeout[2];
  
  if (pipe(pipein) == -1 || pipe(pipeout) == -1) {
    perror("pipe");
    exit(2);
  }

  // Direct stdin and stdout to relevant pipes and close pipe descriptors
  dup2(pipein[0], 0);
  dup2(pipeout[1], 1);

  close(pipein[0]);
  close(pipeout[1]);

  // Write input to input pipe and close file descriptor
  write(pipein[1], str.c_str(), str.size());
  close(pipein[1]);

  // Create child process with fork)(
  int ret = fork();
  // If child process:
  if (ret == 0) { 
    // Create and execute the subshell process with no arguments, checking for 
    // execvp errors
    char *args[] = {(char *) "/proc/self/exe", NULL};
    execvp(args[0], args);
    
    perror("execvp");
    _exit(1);
  // Error in fork detected, return error state
  } else if (ret < 0) {
    perror("fork");
    exit(2);
  }

  // Wait for subshell to finish executing
  while(waitpid(ret, NULL, 0) == -1);

  // Create buffer with specified initial size and pointer to stay
  // at the start of the buffer 
  char * buffer = (char*) malloc(buffer_size * sizeof(char*));
  char * buffer_start = buffer;

  // Initialize counter of characters read
  int index = 0;
  
  // Give output pipe appropriate flags/permissions so that read command
  // does not hang when all input is read, and instead returns value <= 0.
  fcntl(pipeout[0], F_SETFL, O_NONBLOCK);

  // Read from buffer each character one by one, replacing newline characters with spaces
  // and resizing buffer as necessary with realloc().
  while(read(pipeout[0], buffer, 1) > 0) {
    if(*buffer == '\n') {*buffer = ' ';} 
    index++;
    buffer++;
    if(index == buffer_size) {
      buffer_size *= 2; 
      buffer_start = (char*) realloc(buffer_start, buffer_size * sizeof(char*));
    }
  }
  
  // Reset primary buffer pointer to the start of the buffer, close output pipe, and
  // add a null terminator.
  buffer = buffer_start;
  buffer[index - 1] = '\0';  
  close(pipeout[0]);  
  
  // For all output characters, excluding the twelve
  // characters that make up the shell process goodbye
  // message, call yyunput() to pass to input buffer yytext.
  for(int i = index - 12; i >= 0; i--) {
    yyunput(buffer[i], yytext);
  }

  // Deallocate buffer
  free(buffer);

  // Redirect stdin/stdout to defaults and close file descriptors
  dup2(defaultin, 0);
  dup2(defaultout, 1);

  close(defaultin);
  close(defaultout);

}


((\\[^nt])|[^ \\\t\n\|<>])*\"((\\[^nt])|[^\\\n])*\"((\\[^nt])|[^ \\\t\n\|<>])* {
  // Initialize string and counter to track quotes and escape characters
  std::string escape_quote_str = std::string(yytext);
  int quote_count = 0;
  int slash_idx = escape_quote_str.find('/', 0);
  
  // TILDE EXPANSION: Check for all valid cases using tilde expansion and replace with appropriate automatic 
  // path, either the HOME environmental variable or a specific user home (hard coded). Adjusts quote_count
  // when necessary to maintain accuracy.
  if ( escape_quote_str.at(0) == '~' && escape_quote_str.at(1) == '/') {
    escape_quote_str.erase(0, 1);
    escape_quote_str = getenv("HOME") + escape_quote_str;
  } else if ( escape_quote_str.length() >= 2 && escape_quote_str.at(0) == '\"' && escape_quote_str.at(1) == '~' && escape_quote_str.at(2) == '/' ) {
    escape_quote_str.erase(0, 2);
    escape_quote_str = getenv("HOME") + escape_quote_str;
    quote_count--;
  } else if ( escape_quote_str.at(0) == '~' && slash_idx != std::string::npos ) {
    std::string user = escape_quote_str.substr(1, slash_idx - 1);
    escape_quote_str.erase(0, slash_idx);
    escape_quote_str = "/homes/" + user + escape_quote_str;
  } else if ( escape_quote_str.at(0) == '\"' && escape_quote_str.at(1) == '~' && slash_idx != std::string::npos ) {
    std::string user = escape_quote_str.substr(2, slash_idx - 2);
    escape_quote_str.erase(0, slash_idx);
    escape_quote_str = "/homes/" + user + escape_quote_str;
    quote_count--;
  } else if ( escape_quote_str.at(0) == '\"' && escape_quote_str.at(1) == '~' && escape_quote_str.at(2) != '\"' ) {
    escape_quote_str.erase(0, 2);
    escape_quote_str = "/homes/" + escape_quote_str;
    quote_count--;
  } else if ( escape_quote_str.at(0) == '\"' && escape_quote_str.at(1) == '~') {
    escape_quote_str.erase(0, 2);
    escape_quote_str = getenv("HOME") + escape_quote_str;
    quote_count--;
  }

  // Find first instance of quote, if present
  size_t str_idx = escape_quote_str.find('\"', 0);
  // While an instance of quotes that are not escape characters are still in the string, 
  // remove them from the input string and add to quote counter.
  while (str_idx != std::string::npos) {
     if (str_idx == 0) {
        escape_quote_str = escape_quote_str.substr(str_idx + 1, std::string::npos);
        quote_count++;
     } else if (escape_quote_str.at(str_idx - 1) != '\\') {
        escape_quote_str = escape_quote_str.substr(0, str_idx) + escape_quote_str.substr(str_idx + 1, std::string::npos);
        quote_count++;
     } else {str_idx++;}
     str_idx = escape_quote_str.find('\"', str_idx);
  }
  // If an odd number of quotes are present, return a syntax error.
  if (quote_count % 2 == 1) return NOTOKEN;

  // ENVIRONMENTAL VARIABLES: Exapnd evironmental variables when necessary. Includes custom built-in environmenal
  // variables.
  str_idx = escape_quote_str.find('$', 0);
  while (str_idx != std::string::npos && escape_quote_str.length() - (str_idx + 1) > 0) {
    if (str_idx == 0) {
      escape_quote_str = escape_quote_str.substr(str_idx + 1, std::string::npos);
    } else if (escape_quote_str.at(str_idx - 1) != '\\') {
      escape_quote_str = escape_quote_str.substr(0, str_idx) + escape_quote_str.substr(str_idx + 1, std::string::npos);
    } else {str_idx = escape_quote_str.find('$', str_idx); continue;}      
    if (escape_quote_str.at(str_idx) == '{') {
        size_t end_idx = escape_quote_str.find('}', str_idx);
        if (end_idx != std::string::npos) {
          std::string component = escape_quote_str.substr(str_idx + 1, end_idx - str_idx - 1);
          std::string result = "";
          if ( strcmp(component.c_str(), "$") == 0) {
            result += std::to_string(getpid());
          } else if ( strcmp(component.c_str(), "?") == 0) {
             result += std::to_string(Shell::_returnStatus);
          } else if ( strcmp(component.c_str(), "!") == 0) {
            result += std::to_string(Shell::_bkgPIDs.back());
          } else if ( strcmp(component.c_str(), "_") == 0) {
            result += Shell::_currentCommand.getLastArgument();
          } else if ( strcmp(component.c_str(), "SHELL") == 0) {
            char path[1024];
	    realpath("../shell", path);
            result += std::string(path);
          } else if (getenv(component.c_str())) {
              result += std::string(getenv(component.c_str()));
          } else {
            return NOTOKEN;
          }
          escape_quote_str = escape_quote_str.substr(0, str_idx) + result + escape_quote_str.substr(end_idx + 1, std::string::npos);
        } else {return NOTOKEN;}
    }
    str_idx = escape_quote_str.find('$', str_idx);
  }

  // Find first instance of escape character, if present.
  size_t idx = escape_quote_str.find('\\', 0);
  // While an instance of an escape character is still in the string, remove it.
  while (idx != std::string::npos) {
     if (idx != 0) {
        escape_quote_str = escape_quote_str.substr(0, idx) + escape_quote_str.substr(idx + 1, std::string::npos);
     } else {
        escape_quote_str = escape_quote_str.substr(idx + 1, std::string::npos);
     }
     idx = escape_quote_str.find('\\', idx + 1);
  }
  // Set up and return processed word to grammar.
  yylval.cpp_string = new std::string(escape_quote_str);
  return WORD;
}

(((\\[^nt])|([^ \\\t\n\|<>]))|(\`[^\n\`]*\`|$\([^\n]*\)))+ {
  // For strings with possible escape characters that do not include quotes,
  // handle escape characters with a while loop utilizing same method.
  std::string escape_str = std::string(yytext);
  bool expansion = false;
  int slash_idx = escape_str.find('/', 0);

  // ENVIRONMENTAL VARIABLES: Exapnd evironmental variables when necessary. Includes custom built-in environmenal
  // variables. 
  size_t str_idx = escape_str.find('$', 0);
  while (str_idx != std::string::npos && escape_str.length() - (str_idx + 1) > 0) {
    if (str_idx == 0) {
      escape_str = escape_str.substr(str_idx + 1, std::string::npos);
    } else if (escape_str.at(str_idx - 1) != '\\') {
      escape_str = escape_str.substr(0, str_idx) + escape_str.substr(str_idx + 1, std::string::npos);
    } else {str_idx = escape_str.find('$', str_idx); continue;}      
    if (escape_str.at(str_idx) == '{') {
        size_t end_idx = escape_str.find('}', str_idx);
        if (end_idx != std::string::npos) {
          std::string component = escape_str.substr(str_idx + 1, end_idx - str_idx - 1);
          std::string result = "";
          if ( strcmp(component.c_str(), "$") == 0) {
            result += std::to_string(getpid());
          } else if ( strcmp(component.c_str(), "?") == 0) {
             result += std::to_string(Shell::_returnStatus);
          } else if ( strcmp(component.c_str(), "!") == 0 && Shell::_lastBkgProcess != -1) {
            result += std::to_string(Shell::_lastBkgProcess);
          } else if ( strcmp(component.c_str(), "_") == 0 && Shell::_currentCommand.getLastArgument().size() > 0) {
            result += Shell::_currentCommand.getLastArgument();
          } else if ( strcmp(component.c_str(), "SHELL") == 0) {
            char path[1024];
	    realpath("../shell", path);
            result += std::string(path);
          } else if (getenv(component.c_str())) {
              result += std::string(getenv(component.c_str()));
          } else {
            return NOTOKEN;
          }
          escape_str = escape_str.substr(0, str_idx) + result + escape_str.substr(end_idx + 1, std::string::npos);
        }
    }
    str_idx = escape_str.find('$', str_idx);
  }

  // TILDE EXPANSION: Checks for all valid cases and replaces with appropriate environmental variable
  // or path. 
  if ( escape_str.at(0) == '~' && escape_str.length() == 1 ) {
    escape_str = getenv("HOME");
    expansion = true;
  } else if ( escape_str.at(0) == '~' && escape_str.at(1) == '/') {
    escape_str.erase(0, 1);
    escape_str = getenv("HOME") + escape_str;
    expansion = true;
  } else if ( escape_str.at(0) == '~' && slash_idx != std::string::npos ) {
    std::string user = escape_str.substr(1, slash_idx - 1);
    escape_str.erase(0, slash_idx);
    escape_str = "/homes/" + user + escape_str;
    expansion = true;
  } else if ( escape_str.at(0) == '~') {
    escape_str.erase(0, 1);
    escape_str = "/homes/" + escape_str;
    expansion = true;
  }

  // If tilde expansion happened, quotes should not be checked. Return WORD with current
  // processed string.
  if (expansion) {
    yylval.cpp_string = new std::string(escape_str);
    return WORD;
  }

  // Find excape characters and check for single quotes (if one quote is found, return error)
  //if (escape_str.find('\"', 0) != std::string::npos) {return NOTOKEN;}
  size_t idx = escape_str.find('\\', 0);
  while (idx != std::string::npos) {
     if (idx != 0) {
        escape_str = escape_str.substr(0, idx) + escape_str.substr(idx + 1, std::string::npos);
     } else {
        escape_str = escape_str.substr(idx + 1, std::string::npos);
     }
     idx = escape_str.find('\\', idx + 1);
  }

  // Set up and return processed word to grammar.
  yylval.cpp_string = new std::string(escape_str);
  return WORD;
}
