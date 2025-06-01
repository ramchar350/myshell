#ifndef simplcommand_hh
#define simplecommand_hh

#include <string>
#include <vector>

struct SimpleCommand {

  // Simple command is simply a vector of strings
  std::vector<std::string *> _arguments;
  bool _isPrintenv;
  bool _isSetenv;
  bool _isUnsetenv;
  bool _isSource;
  bool _isCd;

  SimpleCommand();
  ~SimpleCommand();
  void insertArgument( std::string * argument );
  void print();
};

#endif
