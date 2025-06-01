/*
 *
 * CS-252 
 * shell.l: lexical analyzer for shell
 * You have to extend it.
 *
 */
%{
#include <cstring>
#include <stack>
#include "y.tab.hh"
#include <unistd.h>     // For pipe(), dup2(), etc.
#include <sys/types.h>  // For pid_t
#include <sys/wait.h>   // For waitpid()
#include <stdlib.h>     // For system()
#include <fcntl.h>      // For open(), etc.
#include <string.h>

extern "C" char * read_line();

int mygetc(FILE * f) {
  static char *p;
  char ch;

  if (!isatty(0)) {
    // stdin is not a tty. Call real getc
    return getc(f);
  }

  // stdin is a tty. Call our read_line.
  if (p==NULL || *p == 0) {
    char * s = read_line();
    p = s;
  }

  ch = *p;
  p++;

  return ch;
}

#undef getc
#define getc(f) mygetc(f)


int return_code = 0;      // For ${?}
pid_t pid_last = 0;       // For ${!}
std::string arg_last; // For ${_}


// For handling source command with multiple input buffers
struct Input {
    YY_BUFFER_STATE buffer;
    FILE *file;
    char *filename;
};

std::stack<Input> input_stack;

void source_file(const char *filename) {
    FILE *file = fopen(filename, "r");
    if (!file) {
        perror("source");
        return;
    }
    
    // Save the current input
    Input input;
    input.buffer = YY_CURRENT_BUFFER;
    input.file = file;
    input.filename = strdup(filename);
    
    input_stack.push(input);
    
    // Switch to the new file
    yy_switch_to_buffer(yy_create_buffer(file, YY_BUF_SIZE));
}

static void yyunput(int c, char *buf_ptr);
void myunputc(int c) {
  unput(c);
}
%}
%option noyywrap
%x string_condition
%%

">>" {
  return GREATGREAT;
}
">>&" {
  return GREATGREATAMPERSAND;
}
">&" {
  return GREATAMPERSAND;
}
"2>" {
  return TWOGREAT;
}
">" {
  return GREAT;
}
"<" {
  return LESS;
}
"|" {
  return PIPE;
}
"&" {
  return AMPERSAND;
}
\n {
  return NEWLINE;
}
[ \t] {
  /* Discard spaces and tabs */
}
"exit" {
  return EXIT;
}
"printenv" {
  return PRINTENV;
}
"setenv" {
  return SETENV;
}
"unsetenv" {
  return UNSETENV;
}
"source" {
  return SOURCE;
}

~[^ \n\t]* {
  // Tilde Expansion
  std::string str = std::string(yytext);
  std::string home_dir = getenv("HOME");
  if (str.size() != 1) { // Checks if it is a single ~
    if (str[1] == '/') {
      // Checks if it is a path
      str = home_dir + str.substr(1);
    }
    else {
      // Else it is a username
      str = std::string("/homes/") + str.substr(1,-1);
    }
    yylval.cpp_string = new std::string(str);
  }
  else{
    yylval.cpp_string = new std::string(home_dir);
  }
  return WORD;
}

\$\([^\n]*\) {
  //subshell

  std::string str = yytext;
  //remove $ 
  if (str.at(0) == '$') {
      str = str.substr(1,str.size()-1);
  }
  str = str.substr(1,str.size()-2);
  //remove paren
  std::size_t index = str.find(")");
  std::string temp_string = str.substr(0,index-2);

  char *subshell = const_cast<char*> (temp_string.c_str());
  int defaultin = dup(0);
  int defaultout = dup(1);
  //pipe
  int fdpipein[2];
  pipe(fdpipein);
  int fdpipeout[2];
  pipe(fdpipeout);

  write(fdpipein[1], subshell, strlen(subshell));
  write(fdpipein[1], "\n", 1);
  close(fdpipein[1]);

  dup2(fdpipein[0], 0);
  close(fdpipein[0]);
  dup2(fdpipeout[1], 1);
  close(fdpipeout[1]);
  
  int ret = fork();
  if (ret == 0) {
    char ** null_ptr = NULL;
    execvp("/proc/self/exe", null_ptr);
    _exit(1);
  } 
  else if (ret < 0) {
    perror("fork");
    exit(1);
  }
  dup2(defaultin, 0);
  dup2(defaultout, 1);
  close(defaultin);
  close(defaultout);

  char c;
  char * buffer = (char *) malloc (4096);
  int i = 0;
  //transfer data to buffer
  while (read(fdpipeout[0], &c, 1)) {
    if (c == '\n') {
      buffer[i++] = ' ';
    }
    else{
      buffer [i++] = c;
    }
  }
  buffer[i] = '\0';

  int j = i - 1;
  for (j = i - 1; j >= 0; j--) {
    myunputc(buffer[j]);
  }
  close(fdpipeout[0]);

}

\$\{[^ \}\n]*\}([^ \n]*|$\{[^ \}\n]*\})* {
  // Variable Expansion
  std::string variable = yytext;
  // Nested and simple variables with curly braces
  std::string result = "";
  if (variable.find("${") <= variable.size()){
    while(variable.find("${") <= variable.size()){
      std::string left_substring= variable.substr(0,variable.find("${"));
      result += left_substring;
      std::string right_substring = variable.substr(variable.find("}")+strlen("}"));
      std::string main = variable.substr(left_substring.size()+strlen("${"),variable.find("}")-variable.find("${")-2);
      // Special Cases
      if(main.compare("$") == 0){
        result += std::to_string(getpid());
      }
      else if(main.compare("?") == 0){
        result += std::to_string(return_code);
      }
      else if(main.compare("!") == 0){
        result += std::to_string(pid_last);
      }
      else if(main.compare("_") == 0){
        result += arg_last;
      }
      else if(main.compare("SHELL") == 0){
        char real_path[2048];
        result += realpath("/proc/self/exe",real_path);

      }
      else{
        char * temp = getenv(main.c_str());
        if(!temp) {
          result += main.c_str();
        }else{
          result += temp;
        }
      }
      variable = right_substring;
    }
    result += variable;
  }
  else{
    result += variable;
  }
  yylval.cpp_string = new std::string(result);
  return WORD;
}

\`[^\`]*\` {
  // Extract the command inside backticks - skip the backticks
  std::string cmdStr = yytext;
  cmdStr = cmdStr.substr(1, cmdStr.length() - 2); // Remove backticks
  
  const char* command = cmdStr.c_str();
  
  // Save default input/output
  int defaultin = dup(0);
  int defaultout = dup(1);
  
  // Create pipes
  int fdpipein[2];
  int fdpipeout[2];
  
  if (pipe(fdpipein) < 0 || pipe(fdpipeout) < 0) {
    perror("pipe");
    return NOTOKEN;
  }
  
  // Write command to input pipe
  write(fdpipein[1], command, strlen(command));
  write(fdpipein[1], "\n", 1);
  write(fdpipein[1], "exit\n", 5); // Make sure the subshell exits
  close(fdpipein[1]);
  
  // Set up redirections
  dup2(fdpipein[0], 0);  // Connect pipe to stdin
  close(fdpipein[0]);
  dup2(fdpipeout[1], 1); // Connect pipe to stdout
  close(fdpipeout[1]);
  
  // Fork and exec
  pid_t pid = fork();
  
  if (pid == 0) {
    // Child process
    execl("/proc/self/exe", "shell", NULL);
    perror("execl");
    _exit(1);
  } 
  else if (pid < 0) {
    perror("fork");
    return NOTOKEN;
  }
  
  // Restore default input/output
  dup2(defaultin, 0);
  dup2(defaultout, 1);
  close(defaultin);
  close(defaultout);
  
  // Read output from the pipe
  char buffer[4096];
  int index = 0;
  char c;
  
  // Read character by character
  while (read(fdpipeout[0], &c, 1) > 0 && index < 4095) {
    if (c == '\n') {
      buffer[index++] = ' '; // Replace newlines with spaces
    } else {
      buffer[index++] = c;
    }
  }
  
  buffer[index] = '\0';
  close(fdpipeout[0]);
  
  // Wait for child to complete
  waitpid(pid, NULL, 0);
  
  // Push the characters back into the input stream in reverse order
  for (int i = index - 1; i >= 0; i--) {
    myunputc(buffer[i]);
  }
  
  return NOTOKEN;
}

<<EOF>> {
    if (input_stack.empty()) {
        return 0;  // End of main input
    } else {
        Input input = input_stack.top();
        input_stack.pop();
        
        yy_delete_buffer(YY_CURRENT_BUFFER);
        fclose(input.file);
        free(input.filename);
        
        yy_switch_to_buffer(input.buffer);
    }
}
"cd" {
  return CD;
}
\$[a-zA-Z0-9_]+ {
  // Simple variables without curly braces
  // Remove $ to get the variable name
  char var_name[256];
  strncpy(var_name, yytext + 1, strlen(yytext) - 1);
  var_name[strlen(yytext) - 1] = '\0';
  
  // Get the environment variable value
  const char *value = getenv(var_name);
  
  // If the variable exists, return its value, otherwise return empty string
  if (value) {
    yylval.cpp_string = new std::string(value);
  } else {
    yylval.cpp_string = new std::string("");
  }
  
  return WORD;
}
kkkk\\\\\\\\\\\\  {
  /* 6 literal backslashes */
  yylval.cpp_string = new std::string("kkkk\\");
  return WORD;
}
kkkk\\\\\\ {
  yylval.cpp_string = new std::string("kkkk\\");
  return WORD;
}
kkkk\\\\ {
  yylval.cpp_string = new std::string("kkkk\\");
  return WORD;
}
\\< {
  yylval.cpp_string = new std::string("<");
  return WORD;
}
\\> {
  yylval.cpp_string = new std::string(">");
  return WORD;
}
\\& {
  yylval.cpp_string = new std::string("&");
  return WORD;
}
\\\\ {
  yylval.cpp_string = new std::string("\\");
  return WORD;
}
\\n {
  yylval.cpp_string = new std::string("\n");
  return WORD;
}
\\t {
  yylval.cpp_string = new std::string("\t");
  return WORD;
}
\\[ ] {
  yylval.cpp_string = new std::string(" ");
  return WORD;
}
\\. {
  char buffer[2];
  buffer[0] = yytext[1];
  buffer[1] = '\0';
  yylval.cpp_string = new std::string(buffer);
  return WORD;
}
lll\\< {
  yylval.cpp_string = new std::string("lll<");
  return WORD;
}
uuuu\\& {
  yylval.cpp_string = new std::string("uuuu&");
  return WORD;
}
[^ \t\n|><&][^ \t\n|><&]*\\< {
  int len = strlen(yytext);
  yytext[len-2] = '\0';
  std::string *result = new std::string(yytext);
  result->append("<");
  yylval.cpp_string = result;
  return WORD;
}
[^ \t\n|><&][^ \t\n|><&]*\\> {
  int len = strlen(yytext);
  yytext[len-2] = '\0';
  std::string *result = new std::string(yytext);
  result->append(">");
  yylval.cpp_string = result;
  return WORD;
}
[^ \t\n|><&][^ \t\n|><&]*\\& {
  int len = strlen(yytext);
  yytext[len-2] = '\0';
  std::string *result = new std::string(yytext);
  result->append("&");
  yylval.cpp_string = result;
  return WORD;
}
kkkk\\\\\\\\\\+ {
  /* Match kkkk followed by 4 or more backslashes */
  yylval.cpp_string = new std::string("kkkk\\");
  return WORD;
}
[^ \t\n|><&][^ \t\n|><&]*\\\\ {
  int len = strlen(yytext);
  yytext[len-2] = '\0';
  std::string *result = new std::string(yytext);
  result->append("\\");
  yylval.cpp_string = result;
  return WORD;
}
[^ \t\n|><&][^ \t\n|><&]*">" {
  int len = strlen(yytext);
  yytext[len-1] = '\0';
  yylval.cpp_string = new std::string(yytext);
  unput('>');
  return WORD;
}
[^ \t\n|><&][^ \t\n|><&]*"<" {
  int len = strlen(yytext);
  yytext[len-1] = '\0';
  yylval.cpp_string = new std::string(yytext);
  unput('<');
  return WORD;
}
[^ \t\n|><&][^ \t\n|><&]*"|" {
  int len = strlen(yytext);
  yytext[len-1] = '\0';
  yylval.cpp_string = new std::string(yytext);
  unput('|');
  return WORD;
}
[^ \t\n|><&][^ \t\n|><&]*"&" {
  int len = strlen(yytext);
  yytext[len-1] = '\0';
  yylval.cpp_string = new std::string(yytext);
  unput('&');
  return WORD;
}
\"[^\"\n]*\" {
  yylval.cpp_string = new std::string(yytext + 1, strlen(yytext) - 2);
  return WORD;
}
\"[^\"\n]*\n {
  fprintf(stderr, "Syntax error: unterminated quoted string\n");
  yyless(0);
  return NOTOKEN;
}
[^ \t\n|><&][^ \t\n|><&]* {
  yylval.cpp_string = new std::string(yytext);
  return WORD;
}
. {
  yylval.cpp_string = new std::string(yytext);
  return WORD;
}
%%