
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
%token NOTOKEN GREAT NEWLINE PIPE GREATGREAT AMPERSAND LESS GREATAMPERSAND GREATGREATAMPERSAND TWOGREAT EXIT PRINTENV SETENV UNSETENV SOURCE CD

%{
//#define yylex yylex
#include <cstdio>
#include "shell.hh"
#include <dirent.h>
#include <regex.h>
#include <vector>
#include <algorithm>
#include <unistd.h>
#include <cstring>

extern char **environ;

void yyerror(const char * s);
void expandWildcard(char * prefix, char * suffix);
bool string_equality(char * a, char * b);
int yylex();

static std::vector<char *> _sortArgument = std::vector<char *>();
bool wildCard = false;
bool find = false;

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
  simple_command
  | exit_command
  ;

exit_command:
  EXIT NEWLINE {
    printf("Good bye!!\n");
    exit(0);
  }
  ;

simple_command:
  pipe_list iomodifier_opt AMPERSAND NEWLINE {
    if (Shell::_debug) {
      printf("   Yacc: Execute command in background\n");
    }
    Shell::_currentCommand._background = true;
    Shell::_currentCommand.execute();
  }
  | pipe_list iomodifier_opt NEWLINE {
    if (Shell::_debug) {
      printf("   Yacc: Execute command\n");
    }
    Shell::_currentCommand.execute();
  }
  | NEWLINE 
  | error NEWLINE { yyerrok; }
  ;

pipe_list:
  simple_command_and_args
  | pipe_list PIPE simple_command_and_args
  ;

simple_command_and_args:
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
    if (Shell::_debug) {
      printf("   Yacc: insert argument \"%s\"\n", $1->c_str());
    }

    wildCard = false;
    char *p = (char *)"";
    expandWildcard(p, (char *)$1->c_str());
    std::sort(_sortArgument.begin(), _sortArgument.end(), string_equality);
    for (auto a: _sortArgument) {
      std::string * argToInsert = new std::string(a);
      Command::_currentSimpleCommand->insertArgument(argToInsert);
    }
    _sortArgument.clear();
  }
  ;

command_word:
  WORD {
    if (Shell::_debug) {
      printf("   Yacc: insert command \"%s\"\n", $1->c_str());
    }
    Command::_currentSimpleCommand = new SimpleCommand();
    Command::_currentSimpleCommand->insertArgument( $1 );
  }
  | PRINTENV {
    if (Shell::_debug) {
      printf("   Yacc: insert command \"printenv\"\n");
    }
    Command::_currentSimpleCommand = new SimpleCommand();
    std::string *printenv_str = new std::string("printenv");
    Command::_currentSimpleCommand->insertArgument(printenv_str);
    Command::_currentSimpleCommand->_isPrintenv = true;
  }
  | SETENV {
    if (Shell::_debug) {
      printf("   Yacc: insert command \"setenv\"\n");
    }
    Command::_currentSimpleCommand = new SimpleCommand();
    std::string *setenv_str = new std::string("setenv");
    Command::_currentSimpleCommand->insertArgument(setenv_str);
    Command::_currentSimpleCommand->_isSetenv = true;
  }
  | UNSETENV {
    if (Shell::_debug) {
      printf("   Yacc: insert command \"unsetenv\"\n");
    }
    Command::_currentSimpleCommand = new SimpleCommand();
    std::string *unsetenv_str = new std::string("unsetenv");
    Command::_currentSimpleCommand->insertArgument(unsetenv_str);
    Command::_currentSimpleCommand->_isUnsetenv = true;
  }
  | SOURCE {
    if (Shell::_debug) {
      printf("   Yacc: insert command \"source\"\n");
    }
    Command::_currentSimpleCommand = new SimpleCommand();
    std::string *source_str = new std::string("source");
    Command::_currentSimpleCommand->insertArgument(source_str);
    Command::_currentSimpleCommand->_isSource = true;
  }
  | CD {
    if (Shell::_debug) {
      printf("   Yacc: insert command \"cd\"\n");
    }
    Command::_currentSimpleCommand = new SimpleCommand();
    std::string *cd_str = new std::string("cd");
    Command::_currentSimpleCommand->insertArgument(cd_str);
    Command::_currentSimpleCommand->_isCd = true;
  }
  ;

iomodifier_opt:
  iomodifier_list
  ;

iomodifier_list:
  /* empty */
  | iomodifier_list iomodifier
  ;

iomodifier:
  GREAT WORD {
    if (Shell::_debug) {
      printf("   Yacc: insert output \"%s\"\n", $2->c_str());
    }
    if (Shell::_currentCommand._outFile != NULL) {
      fprintf(stderr, "Ambiguous output redirect.\n");
      Shell::_currentCommand._ambiguousRedirect = true;
    }
    Shell::_currentCommand._outFile = $2;
    Shell::_currentCommand._append = false;
  }
  | LESS WORD {
    if (Shell::_debug) {
      printf("   Yacc: insert input \"%s\"\n", $2->c_str());
    }
    Shell::_currentCommand._inFile = $2;
  }
  | TWOGREAT WORD {
    if (Shell::_debug) {
      printf("   Yacc: insert error \"%s\"\n", $2->c_str());
    }
    Shell::_currentCommand._errFile = $2;
  }
  | GREATAMPERSAND WORD {
    if (Shell::_debug) {
      printf("   Yacc: insert output/error \"%s\"\n", $2->c_str());
    }
    if (Shell::_currentCommand._outFile != NULL) {
      fprintf(stderr, "Ambiguous output redirect.\n");
      Shell::_currentCommand._ambiguousRedirect = true;
    }
    Shell::_currentCommand._outFile = $2;
    Shell::_currentCommand._errFile = $2;
  }
  | GREATGREAT WORD {
    if (Shell::_debug) {
      printf("   Yacc: append output \"%s\"\n", $2->c_str());
    }
    if (Shell::_currentCommand._outFile != NULL) {
      fprintf(stderr, "Ambiguous output redirect.\n");
      Shell::_currentCommand._ambiguousRedirect = true;
    }
    Shell::_currentCommand._outFile = $2;
    Shell::_currentCommand._append = true;
  }
  | GREATGREATAMPERSAND WORD {
    if (Shell::_debug) {
      printf("   Yacc: append output/error \"%s\"\n", $2->c_str());
    }
    if (Shell::_currentCommand._outFile != NULL) {
      fprintf(stderr, "Ambiguous output redirect.\n");
      Shell::_currentCommand._ambiguousRedirect = true;
    }
    Shell::_currentCommand._outFile = $2;
    Shell::_currentCommand._errFile = $2;
    Shell::_currentCommand._append = true;
  }
  | /* can be empty */ 
  ;

%%

void
yyerror(const char * s)
{
  fprintf(stderr,"%s", s);
}

bool string_equality (char * a, char * b) { 
  return strcmp(a,b)<0; 
}

void expandWildcard(char * prefix, char * suffix) {
  // Wildcard Functionality
  // Empty Case
  if (suffix[0] == 0) {
    _sortArgument.push_back(strdup(prefix));
    return;
  }
  // Sets up prefix
  char Prefix[1024];
  char newPrefix[1024];
  if (prefix[0] == 0) {
    if (suffix[0] == '/') {
      suffix += 1;
      sprintf(Prefix, "%s/", prefix);
    }
    else{
      strcpy(Prefix, prefix);
    }
  }
  else{
    sprintf(Prefix, "%s/", prefix);
  }
  // Parses suffix
  char * s = strchr(suffix, '/');
  char component[1024];
  if (s != NULL) {
    strncpy(component, suffix, s-suffix);
    component[s-suffix] = 0;
    suffix = s + 1;
  }
  else {
    strcpy(component, suffix);
    suffix = suffix + strlen(suffix);
  }

  // If no wildcard is present, traverse through directory
  if (strchr(component,'?')== NULL && strchr(component,'*') == NULL) {
    if (Prefix[0] == 0){
      strcpy(newPrefix, component);
    }
    else{
      sprintf(newPrefix, "%s/%s", prefix, component);
    }
    expandWildcard(newPrefix, suffix);
    return;
  }

  // If it contains a wildcard

  char * reg = (char*)malloc(2*strlen(component)+10);
  char * r = reg;
  *r = '^'; r++;
  int i = 0;
  while (component[i]) {
    if (component[i] == '*') {
      *r='.'; r++; *r='*'; r++;
    }
    else if (component[i] == '?') {
      *r='.'; r++;
    }
    else if (component[i] == '.') {
      *r='\\'; r++; *r='.'; r++;
    }
    else {
      *r=component[i]; r++;
    }
    i++;
  }

  *r='$'; r++; *r=0;
  regex_t re;
  int expbuf = regcomp(&re, reg, REG_EXTENDED|REG_NOSUB); // Error handling

  char * dir;
  if (Prefix[0] == 0){
    dir = (char*)".";
  }
  else{ 
    dir = Prefix;
  }
  DIR * d = opendir(dir);
  if (d == NULL) {
    return;
  }

  struct dirent * ent;
  while ((ent = readdir(d)) != NULL) {
    if(regexec(&re, ent->d_name, 1, NULL, 0) == 0) {
      find = true;
      if (Prefix[0] == 0){
        strcpy(newPrefix, ent->d_name);
      }
      else {
        sprintf(newPrefix, "%s/%s", prefix, ent->d_name);
      }

      // Hidden file check
      if (reg[1] == '.') {
        if (ent->d_name[0] != '.') expandWildcard(newPrefix, suffix);
      } else{
        expandWildcard(newPrefix, suffix);
      }
    }
  }
  if (!find) {
    if (Prefix[0] == 0){
      strcpy(newPrefix, component);
    }
    else {
      sprintf(newPrefix, "%s/%s", prefix, component);
    }
    expandWildcard(newPrefix, suffix);
  }
  closedir(d);
  regfree(&re);
  free(reg);


}

#if 0
main()
{
  yyparse();
}
#endif
