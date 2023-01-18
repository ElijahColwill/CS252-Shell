
/*
 * CS-252
 * shell.y: parser for shell
 *
 * This parser compiles the following grammar:
 *
 *	cmd [arg]* [> filename]
 *
 * you must extend it to understand the complete shell grammar
 *
 */

%code requires 
{
#include <string>

#if __cplusplus > 199711L
#define register      // Deprecated in C++11 so remove the keyword
#endif
}

%union
{
  char        *string_val;
  // Example of using a c++ type in yacc
  std::string *cpp_string;
}

%token <cpp_string> WORD
%token NOTOKEN GREAT LESS GREATGREAT GREATAMP GREATGREATAMP TWOGREAT PIPE AMP NEWLINE

%{
//#define yylex yylex
#include <cstdio>
#include <sys/types.h>
#include <regex.h>
#include <string>
#include <string.h>
#include <dirent.h>
#include "shell.hh"

void yyerror(const char * s);
int yylex();

void expandWildcardsIfNecessary(std::string * argument);
void expandWildcard(std::string * prefix, std::string * argument);
int comparator(const void * s1, const void * s2);

%}

%%

goal:
  commands
  ;

commands:
  command
  | commands command
  ;

command:	
  pipe_list io_list_opt bkg_opt NEWLINE {
    //printf("   Yacc: Execute command\n");
    Shell::_currentCommand.execute();
  }
  | NEWLINE {Shell::_currentCommand.execute();} 
  | error NEWLINE { yyerrok; }
  ;

pipe_list:
  pipe_list PIPE command_and_args
  | command_and_args
  ;

bkg_opt:
  AMP {
    Shell::_currentCommand._background = true;
  }
  | /* empty */
  ;

command_and_args:
  command_word argument_list {
    Shell::_currentCommand.
    insertSimpleCommand( Command::_currentSimpleCommand );
  }
  ;

argument_list:
  argument_list argument
  | /* can be empty */
  ;

argument:
  WORD {
    //printf("   Yacc: insert argument \"%s\"\n", $1->c_str());
    expandWildcardsIfNecessary( $1 );
  }
  ;

command_word:
  WORD {
    //printf("   Yacc: insert command \"%s\"\n", $1->c_str());
    Command::_currentSimpleCommand = new SimpleCommand();
    Command::_currentSimpleCommand->insertArgument( $1 );
  }
  ;

io_list_opt:
  io_list_opt iomodifier_opt
  | /* empty */
  ;

iomodifier_opt:
  GREAT WORD {
    if (Shell::_currentCommand._outFile) {
      fprintf(stderr, "Ambiguous output redirect.\n");
    } else {
      //printf("   Yacc: insert output GREAT \"%s\"\n", $2->c_str());
      Shell::_currentCommand._outFile = $2;
    }
  }
  | LESS WORD {
    if (Shell::_currentCommand._inFile) {
      fprintf(stderr, "Ambiguous input redirect.\n"); 
    } else {
      //printf("   Yacc: insert output LESS \"%s\"\n", $2->c_str());
      Shell::_currentCommand._inFile = $2;
    }
  }
  | GREATGREAT WORD {
    if (Shell::_currentCommand._outFile) {
      fprintf(stderr, "Ambiguous output redirect.\n");
    } else {
      //printf("   Yacc: insert output GREATGREAT \"%s\"\n", $2->c_str());
      Shell::_currentCommand._outFile = $2;
      Shell::_currentCommand._append = true;
    }
  }
  | GREATAMP WORD {
    if (Shell::_currentCommand._outFile) {
      fprintf(stderr, "Ambiguous output redirect.\n");
    } else if (Shell::_currentCommand._errFile) {
      fprintf(stderr, "Ambigous error redirect.\n");
    } else {
      //printf("   Yacc: insert output GREATAMP \"%s\"\n", $2->c_str());
      Shell::_currentCommand._outFile = $2;
      Shell::_currentCommand._errFile = $2;
   }
  }
  | GREATGREATAMP WORD {
    if (Shell::_currentCommand._outFile) {
      fprintf(stderr, "Ambiguous output redirect.\n");
    } else if (Shell::_currentCommand._errFile) {
      fprintf(stderr, "Ambiguous error redirect.\n");
    } else {
      //printf("   Yacc: insert output GREATGREATAMP \"%s\"\n", $2->c_str());
      Shell::_currentCommand._outFile = $2;
      Shell::_currentCommand._errFile = $2;
      Shell::_currentCommand._append = true;
    }
  }
  | TWOGREAT WORD {
    if (Shell::_currentCommand._errFile) {
      fprintf(stderr, "Ambiguous error redirect.\n");
    } else {
      //printf("   Yacc: insert output TWOGREAT \"%s\"\n", $2->c_str());
      Shell::_currentCommand._errFile = $2;
    }
  }  
  ;

%%

void
yyerror(const char * s)
{
  fprintf(stderr,"%s\n", s);
  Shell::_currentCommand.clear();
  Shell::prompt();
}

// Comparator function: converts and compares two string arguments for use
// in qsort.
int comparator(const void * s1, const void * s2) {
  const char * i1 = *(const char **) s1;
  const char * i2 = *(const char **) s2;
  return strcmp(i1, i2);
}

// Set global variables for expanding wildcard functions.
char ** array;
int maxEntries;
int numEntries;

// Called on every argument to call recursive wildcard function if * or ? are present.
void expandWildcardsIfNecessary(std::string * argument) {
  // No * or ? present, so argument can be handled normally. Insert argument and return.
  if (!strchr(argument->c_str(), '*') && !strchr(argument->c_str(), '?')) {
    Command::_currentSimpleCommand->insertArgument(argument);
    return;
  }
  
  // Based on input argument, determine if a slash needs to be added to all returned arguments
  // from the recursive function to reflect the absolute path of the argument.
  bool add_slash = false;
  if (argument->at(0) != '*' && 
     (argument->length() < 2 || (argument->at(0) != '.' && argument->at(1) != '*')) && 
     argument->find('/', 0) == 0) {add_slash = true;} 

  // Set intital values for numEntries and maxEntires 
  maxEntries = 20;
  numEntries = 0;

  // Allocate array of expanded arguments and call recursive function with a 
  // starting prefix of NULL.
  array = (char **) malloc((maxEntries) * sizeof(char *));
  expandWildcard(NULL, argument);

  // Sort created arguements according to custom comparator in ascending order.
  qsort(array, numEntries, sizeof(char *), comparator);  

  // Loop through all expanded arguments, add slash if necessary, and insert into
  // current simple command.
  for (int i = 0; i < numEntries; i++) {
    std::string str_argument = std::string(array[i]);
    if (add_slash) str_argument = '/' + str_argument;
    std::string * str_ptr = new std::string(str_argument);
    Command::_currentSimpleCommand->insertArgument(str_ptr);
  }
   
  // Deallocate all allocated arguments, including the passed argument if it was expanded.
  for (int i = 0; i < numEntries; i++) {free(array[i]);}
  delete argument;
  free(array);
}


// Recursive wildcard expansion function (passes expanded files into global
// array variable and returns void. Takes in prefix and "suffix" (argument string)
// arguments.
void expandWildcard(std::string * prefix, std::string * argument) {
  // If no suffix exists, we have expanded as far as required and
  // insert the created argument into the array.
  if (argument->length() == 0 || argument == NULL) {
    // If current capacity of array is reached, reallocate array with more memory.
    if (numEntries == maxEntries) {
      maxEntries *= 2;
      array = (char **) realloc(array, maxEntries * sizeof(char *));
    }
    // Insert current expansion into array and return from function.
    array[numEntries++] = strdup((char *) prefix->c_str());
    return;
  }

  // Create strings on stack to hold temporary current directory and 
  // temporary argument..
  std::string temp_dir;
  std::string temp_str(argument->c_str());

  // If argument starts with a slash, erase that slash from the temporary
  // argument. 
  if (argument->c_str()[0] == '/') {
    temp_str.erase(0, 1);
  }

  // Set temporary directory and argument to correct values to continue expanding based
  // on current location of the next slash (next level).
  int found_idx = temp_str.find('/');
  if (found_idx != std::string::npos) {
    temp_dir = temp_str.substr(0, found_idx);
    temp_str = temp_str.substr(found_idx + 1, std::string::npos);
  } else {
    temp_dir = temp_str;
    temp_str = "";
  }
   
  // If * and ? are not in the current level, no expansion is necessary. Create, allocate, and 
  // deallocate appropriate arguments to call recursive function on the next level based on if
  // a prefix exists for this call.
  if (temp_dir.find('*') == std::string::npos && temp_dir.find('?') == std::string::npos) {
    std::string * passed_suffix = new std::string(temp_str);
    std::string * passed_prefix;
    if (!prefix || prefix->length() == 0) {
      passed_prefix = new std::string(temp_dir);
      expandWildcard(passed_prefix, passed_suffix);
      delete passed_prefix;
      delete passed_suffix;
      return;
    }
    std::string build(prefix->c_str());
    build += "/" + temp_dir;
    passed_prefix = new std::string(build);
    expandWildcard(passed_prefix, passed_suffix);
    delete passed_prefix;
    delete passed_suffix;
    return;
  }

  // Create custom prefix to handle opening directory 
  // correctly when searching for matches.  
  std::string newPrefix;
  if (!prefix && argument->c_str()[0] == '/') {
    newPrefix = "/";
  } else if (!prefix) {
    newPrefix = "";
  } else {
    newPrefix = std::string(prefix->c_str());
  }

  // Set up buffer and reserved memory to crate regex, and set first character of 
  // regex to '^'
  char * temp = (char *) temp_dir.c_str();
  char * reserved = (char *) malloc((2 * argument->length()) + 10 * sizeof(char *));
  char * save = reserved;

  *save = '^';
  save++;
  
  // While there are characters left in the current level, process them to 
  // create the regex and store it in save.
  while(*temp) {
    if (*temp == '*') {*save = '.'; save++; *save = '*';}
    else if (*temp == '?') {*save = '.';}
    else if (*temp == '.') {*save = '\\'; save++; *save = '.';}
    else {*save = *temp;}
    temp++;
    save++;
  }

  // Add $ and null terminator to regex.
  *save = '$';
  save++;
  *save = '\0';


  // Compile regex and check for errors.
  regex_t re;

  if (regcomp(&re, reserved, REG_EXTENDED | REG_NOSUB) != 0) {
    perror("compile");
    exit(1);
  }

  // Create string that will be used to search for a match
  // with opendir() based on newPrefix
  char * open;
  std::string builtOpen;
  if (newPrefix.length() == 0) {
    open = strdup(".");
    builtOpen = std::string(open);
  } else {
    open = strdup(newPrefix.c_str());
    builtOpen = std::string(open);
    builtOpen = "/" + builtOpen;
  }
  
  // Create DIR to hold opendir() returb.
  DIR * dir = opendir(builtOpen.c_str());

  // If opendir() did not match, then attempt to open the same
  // directory utilizing relative instead of absolute paths.
  // If the relative path also does not find a match, no matches
  // were found and return from function.
  if (dir == NULL) {
    char attempt_buffer[PATH_MAX];
    builtOpen = "." + builtOpen;
    char * attempt_path = realpath(builtOpen.c_str(), attempt_buffer);
    if (attempt_path) {
      dir = opendir(attempt_path);
      if (dir == NULL) return; 
    } else {return;}
  }

  // Initialize variables necessary to search for matching files.
  struct dirent * ent;
  regmatch_t match;
  bool found = false;

  // White matches are found from matched directory, create and adjust the prefix
  // and suffix of the new location and call the recursive variable to either add the 
  // match to array or continue expanding in the next level. Deallocate allocated
  // arguments after the function call is completed.
  while ( (ent = readdir(dir)) != NULL ) {
    if (regexec(&re, ent->d_name, 1, &match, 0) == 0) {
      char * send_str = (char *) malloc(1024 * sizeof(char));
      found = true;
      if (!prefix || prefix->length() == 0) {
        sprintf(send_str, "%s", ent->d_name);
      } else {
        sprintf(send_str, "%s/%s", prefix->c_str(), ent->d_name);
      }
      std::string * passed_suffix = new std::string(temp_str);
      std::string * passed_prefix = new std::string(send_str);
      if (ent->d_name[0] == '.' && temp_dir[0] == '.') {
        expandWildcard(passed_prefix, passed_suffix);
      } else if (ent->d_name[0] != '.') {
        expandWildcard(passed_prefix, passed_suffix);
      }
      free(send_str);
      delete passed_suffix;
      delete passed_prefix;
    }
  }

  // If no matches were found and no total entries have been added, then the original given string
  // was not actually a wildcard and no expansion/recursion was done. Instead, all the argument with
  // the givne prefix and suffix unmodified to new prefix/suffix arguments and try the next level/add to
  // array.
  if(!found && numEntries == 0) {
    char * send_str = (char *) malloc(1024 * sizeof(char));
    if (!prefix || prefix->length() == 0) sprintf(send_str, "%s", temp_dir.c_str());
    else sprintf(send_str, "%s/%s", prefix->c_str(), temp_dir.c_str()); 
    std::string * passed_suffix = new std::string(temp_str);
    std::string * passed_prefix = new std::string(send_str);
    expandWildcard(passed_prefix, passed_suffix);
    delete passed_suffix;
    delete passed_prefix;
  }

  // Deallocate all allocated memory for this function call.
  free(open);
  closedir(dir);
  regfree(&re);
  free(reserved);
}

#if 0
main()
{
  yyparse();
}
#endif
