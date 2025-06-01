#ifndef shell_hh
#define shell_hh

#include "command.hh"

struct Shell {

  static void prompt();

  static Command _currentCommand;
  static bool _debug; // Added a debug flag for print statements
};

// Signal Handling functions
void startCommand();
void endCommand();

#endif
