/*
 * CS252: Shell project
 *
 * Template file.
 * You will need to add more code here to execute the command table.
 *
 * NOTE: You are responsible for fixing any bugs this code may have!
 *
 * DO NOT PUT THIS PROJECT IN A PUBLIC REPOSITORY LIKE GIT. IF YOU WANT 
 * TO MAKE IT PUBLICALLY AVAILABLE YOU NEED TO REMOVE ANY SKELETON CODE 
 * AND REWRITE YOUR PROJECT SO IT IMPLEMENTS FUNCTIONALITY DIFFERENT THAN
 * WHAT IS SPECIFIED IN THE HANDOUT. WE OFTEN REUSE PART OF THE PROJECTS FROM  
 * SEMESTER TO SEMESTER AND PUTTING YOUR CODE IN A PUBLIC REPOSITORY
 * MAY FACILITATE ACADEMIC DISHONESTY.
 */

 #include <cstdio>
 #include <cstdlib>
 
 #include <iostream>
 
 #include "command.hh"
 #include "shell.hh"
 
 #include <unistd.h>
 #include <sys/types.h>
 #include <sys/wait.h>
 #include <fcntl.h>
 
 extern pid_t pid_last;
 extern int return_code;
 extern std::string arg_last;
 
 Command::Command() {
     // Initialize a new vector of Simple Commands
     _simpleCommands = std::vector<SimpleCommand *>();
 
     _outFile = NULL;
     _inFile = NULL;
     _errFile = NULL;
     _background = false;
     _append = false;
     _ambiguousRedirect = false;
 }
 
 void Command::insertSimpleCommand( SimpleCommand * simpleCommand ) {
     // add the simple command to the vector
     _simpleCommands.push_back(simpleCommand);
 }
 
 void Command::clear() {
     // deallocate all the simple commands in the command vector
     for (auto simpleCommand : _simpleCommands) {
         delete simpleCommand;
     }
 
     // remove all references to the simple commands we've deallocated
     // (basically just sets the size to 0)
     _simpleCommands.clear();
 
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
 
     _background = false;
     _append = false;
     _ambiguousRedirect = false;
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
     // Don't do anything if there are no simple commands
     if ( _simpleCommands.size() == 0 || _ambiguousRedirect) {
         clear();
         Shell::prompt();
         return;
     }
 
     // Handle setenv command
     if (_simpleCommands.size() == 1 && _simpleCommands[0]->_isSetenv) {
         // Check if we have the right number of arguments
         if (_simpleCommands[0]->_arguments.size() != 3) {
             fprintf(stderr, "setenv: Wrong number of arguments\n");
             clear();
             Shell::prompt();
             return;
         }
 
         // Get the variable name and value
         const char *var = _simpleCommands[0]->_arguments[1]->c_str();
         const char *value = _simpleCommands[0]->_arguments[2]->c_str();
 
         // Set the environment variable
         if (setenv(var, value, 1) < 0) {
             perror("setenv");
         }
 
         clear();
         Shell::prompt();
         return;
     }
 
     // Handle unsetenv command
     if (_simpleCommands.size() == 1 && _simpleCommands[0]->_isUnsetenv) {
         // Check if we have the right number of arguments
         if (_simpleCommands[0]->_arguments.size() != 2) {
             fprintf(stderr, "unsetenv: Wrong number of arguments\n");
             clear();
             Shell::prompt();
             return;
         }
 
         // Get the variable name
         const char *var = _simpleCommands[0]->_arguments[1]->c_str();
 
         // Remove the environment variable
         if (unsetenv(var) < 0) {
             perror("unsetenv");
         }
 
         clear();
         Shell::prompt();
         return;
     }
 
     // Handle source command
     if (_simpleCommands.size() == 1 && _simpleCommands[0]->_isSource) {
         // Check if we have the right number of arguments
         if (_simpleCommands[0]->_arguments.size() != 2) {
             fprintf(stderr, "source: Wrong number of arguments\n");
             clear();
             Shell::prompt();
             return;
         }
 
         // Get the filename
         const char *filename = _simpleCommands[0]->_arguments[1]->c_str();
 
         // Source the file (this will switch buffers in the lexer)
         extern void source_file(const char *filename);
         source_file(filename);
 
         // Clear current command but don't prompt
         clear();
         return;
     }

     // Handle cd command
    if (_simpleCommands.size() == 1 && _simpleCommands[0]->_isCd) {
    const char *dir;
    
        // If no argument is provided, use the HOME environment variable
        if (_simpleCommands[0]->_arguments.size() == 1) {
            dir = getenv("HOME");
            if (!dir) {
                fprintf(stderr, "cd: HOME not set\n");
                clear();
                Shell::prompt();
                return;
            }
        } 
        // Otherwise, use the provided directory
        else if (_simpleCommands[0]->_arguments.size() == 2) {
            dir = _simpleCommands[0]->_arguments[1]->c_str();
        } 
        // Too many arguments
        else {
            fprintf(stderr, "cd: too many arguments\n");
            clear();
            Shell::prompt();
            return;
        }
    
        // Try to change the directory
        if (chdir(dir) < 0) {
            fprintf(stderr, "cd: can't cd to %s\n", dir);
        } 
        // Update PWD environment variable to match the new directory
        else {
            char cwd[1024];
            if (getcwd(cwd, sizeof(cwd)) != NULL) {
                setenv("PWD", cwd, 1);
            } else {
                perror("getcwd");
            }
        }
    
        clear();
        Shell::prompt();
        return;
    }
 
     if (_simpleCommands.size() == 1 && _simpleCommands[0]->_arguments.size() == 1 && _simpleCommands[0]->_isPrintenv) {
         // Save default output
         int defaultout = dup(1);
 
         // Handle output redirection if specified
         if (_outFile) {
             int fdout;
             if (_append) {
                 fdout = open(_outFile->c_str(), O_WRONLY | O_CREAT | O_APPEND, 0644);
             }
             else {
                 fdout = open(_outFile->c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
             }
 
             if (fdout < 0) {
                 perror("shell: output redirection");
                 clear();
                 Shell::prompt();
                 return;
             }
 
             // Redirect stdout to the file
             dup2(fdout, 1);
             close(fdout);
         }
 
             // Execute printenv built-in
             extern char **environ;
             for (int i = 0; environ[i] != NULL; i++) {
                 printf("%s\n", environ[i]);
             }
 
             // Restore stdout
             dup2(defaultout, 1);
             close(defaultout);
 
             // Clear and prompt
             clear();
             Shell::prompt();
             return;
     }
 
     // Print contents of Command data structure
     if (Shell::_debug) {
         print();
     }
 
     // Signal that a command is starting
     startCommand();
 
     // Save default input, output, and error
     int defaultin = dup(0);
     int defaultout = dup(1);
     int defaulterr = dup(2);
 
     // I/O Redirection
     int fdin;
     if (_inFile) {
         fdin = open(_inFile->c_str(), O_RDONLY);
         if (fdin < 0) {
             perror("shell: input redirection");
             // Restore defaults
             dup2(defaultin, 0);
             dup2(defaultout, 1);
             dup2(defaulterr, 2);
             close(defaultin);
             close(defaultout);
             close(defaulterr);
             clear();
             Shell::prompt();
             return;
         }
     }
     else {
         // Use default input
         fdin = dup(defaultin);
     }
 
     int fdout;
     // Single simple command case handling (e.g ls - al)
     int pid;
 
     // Loop through all simple commands and set up processes
     for (size_t i = 0; i < _simpleCommands.size(); i++) {
         // Replace stdin with input file
         dup2(fdin, 0);
         close(fdin);
 
         // Set up output
         if (i == _simpleCommands.size() - 1) {
             // Output Redirection
             if (_outFile) {
                 // Check if we need to append
                 if (_append) {
                     fdout = open(_outFile->c_str(), O_WRONLY | O_CREAT | O_APPEND, 0644);
                 }
                 else {
                     fdout = open(_outFile->c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
                 }
 
                 if (fdout < 0) {
                     perror("shell: output redirection");
                     // Restore defaults
                     dup2(defaultin, 0);
                     dup2(defaultout, 1);
                     dup2(defaulterr, 2);
                     close(defaultin);
                     close(defaultout);
                     close(defaulterr);
                     clear();
                     Shell::prompt();
                     return;
                 }
             }
             else {
                 // Use default output
                 fdout = dup(defaultout);
             }
 
             // Error Redirection
             if (_errFile) {
                 int fderr;
 
                 // Check if we need to append
                 if (_append) {
                     fderr = open(_errFile->c_str(), O_WRONLY | O_CREAT | O_APPEND, 0644);
                 }
                 else {
                     fderr = open(_errFile->c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
                 }
 
                 if (fderr < 0) {
                     perror("shell: error redirection");
                     // Restore defaults
                     dup2(defaultin, 0);
                     dup2(defaultout, 1);
                     dup2(defaulterr, 2);
                     close(defaultin);
                     close(defaultout);
                     close(defaulterr);
                     clear();
                     Shell::prompt();
                     return;
                 }
 
                 // Replace stderr with error file
                 dup2(fderr, 2);
                 close(fderr);
             }
         }
         else {
             // Create a pipe
             int fdpipe[2];
             if (pipe(fdpipe) == -1) {
                 perror("shell: pipe");
                 exit(2);
             }
 
             // Use the pipe as an output
             fdout = fdpipe[1];
 
             // Save the input for the next command
             fdin = fdpipe[0];
         }
 
         // Replace stdin with input file
         dup2(fdout, 1);
         close(fdout);

         // Before forking a child process, store the last argument for ${_}
        if (_simpleCommands[i]->_arguments.size() > 0) {
            size_t argsize = _simpleCommands[i]->_arguments.size();
    
            // If there's only one argument (just the command), use that
            if (argsize == 1) {
                arg_last = *_simpleCommands[i]->_arguments[0];
            } 
            // Otherwise use the last argument (not including redirections)
            else {
                arg_last = *_simpleCommands[i]->_arguments[argsize-1];
            }
        }
 
         // Create new process
         pid = fork();
 
         if (pid == -1) {
             perror("shell: fork");
             exit(2);
         }
 
         if (pid == 0) {
             // Child process
 
             // Reset signal handling to default in child process
             signal(SIGINT, SIG_DFL);
 
             // Special handling for printenv when it's part of a pipeline
             if (_simpleCommands[i]->_isPrintenv) {
                 extern char **environ;
                 for (int i = 0; environ[i] != NULL; i++) {
                     printf("%s\n", environ[i]);
                 }
                 exit(0);
             }
 
             // Convert the simple command into a format for execvp
             // Count the number of arguments
             int argc = _simpleCommands[i]->_arguments.size();
 
             // Create an array of C-strings
             char** argv = new char*[argc + 1]; // +1 for NULL terminator
 
             // Fill the array with arguments
             for (int j = 0; j < argc; j++) {
                 argv[j] = (char *)_simpleCommands[i]->_arguments[j]->c_str();
             }
 
             // Set the last element to NULL to mark the end of the array
             argv[argc] = NULL;
 
             // Execute the command
             execvp(argv[0], argv);
 
             // If execvp fails
             perror("shell: execvp");
             _exit(1);
         }
 
         // Parent continues to the next command in the pipeline
     }
 
     // Restore default input, output, and error
     dup2(defaultin, 0);
     dup2(defaultout, 1);
     dup2(defaulterr, 2);
 
     // Close file descriptors
     close(defaultin);
     close(defaultout);
     close(defaulterr);
 
     // If the command is not a background process, wait for completion
    if (!_background) {
        int status;
        waitpid(pid, &status, 0);
    
        // Set the return code for ${?}
        if (WIFEXITED(status)) {
            return_code = WEXITSTATUS(status);
        } else {
            // If the process was terminated by a signal, set a non-zero return code
            return_code = 1;
        }
    }
    else {
        // For background process, don't wait just print the process ID
        pid_last = pid;
    
        // Only print the [1] pid format if we're in interactive mode
        if (isatty(0)) {
            printf("[%d] %d\n", 1, pid);
        }
    }
 
     // Signal that command has ended
     endCommand();

     //fprintf(stderr, "DEBUG: End of execute(), pid_last = %d\n", pid_last);
 
     // Clear to prepare for next command
     clear();
 
     // Print new prompt
     Shell::prompt();
 }
 
 SimpleCommand * Command::_currentSimpleCommand;
 