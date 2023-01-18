#ifndef shell_hh
#define shell_hh

#include "command.hh"

// Shell Data Structure

struct Shell {

  static void prompt();
  static int source(const char * filename);
  static void process_check(pid_t pid);

  static Command _currentCommand;
  static std::vector<int> _bkgPIDs;
  static bool _source;
  static std::string * _lastArgument;
 
  static int _returnStatus;
  static int _lastBkgProcess;

};

#endif
