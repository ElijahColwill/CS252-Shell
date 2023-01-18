/*
 * CS252: Systems Programming
 * Purdue University
 * Example that shows how to read one line with simple editing
 * using raw terminal.
 */

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#define MAX_BUFFER_LINE 2048

// Externs for external function to set and reset
// terminal mode in shell.
extern void tty_raw_mode(void);
extern void tty_term_mode(void);

// Buffer where line is stored
int line_length;
char line_buffer[MAX_BUFFER_LINE];

// Command history array and initial values.
int history_index = 0;
char * history[2048];
int history_length = 0;

// Print default usage (not required to be updated in handout)
void read_line_print_usage()
{
  char * usage = "\n"
    " ctrl-?       Print usage\n"
    " Backspace    Deletes last character\n"
    " up arrow     See last command in the history\n";

  write(1, usage, strlen(usage));
}

/* 
 * Input a line with some basic editing.
 */
char * read_line() {

  // Set terminal in raw mode
  tty_raw_mode();

  line_length = 0;
  int location = line_length;

  // Read one line until enter is typed
  while (1) {

    // Read one character in raw mode.
    char ch;
    read(0, &ch, 1);
    
    // Printable character and not a backspace
    if (ch >= 32 && ch != 127) {
      // If cursor is at the end of the line, simple insertion can be done 
      if (location == line_length) {	
        // Do echo
        write(1, &ch, 1);
	line_buffer[line_length] = ch;
      // Otherwise, tranfer buffer to temporary memory, write new character,
      // and transfer the original line_buffer back.
      } else {
        char temp_buffer[line_length - location + 1];
	for (int i = 0; i < line_length - location; i++) {
	  temp_buffer[i] = line_buffer[location + i];
	}
	write(1, &ch, 1);
	line_buffer[location] = ch;
	for (int i = 0; i < line_length - location; i++) {
	  line_buffer[location + i + 1] = temp_buffer[i];
	  write(1, &temp_buffer[i], 1);
	}
	// Correct for adding another character by moving cursor back
	// to original position.
	for (int i = 0; i < line_length - location; i++) {
	  ch = 8;
	  write(1, &ch, 1);
	}
      }
      // If max number of character reached return.
      if (line_length == MAX_BUFFER_LINE - 2) break; 
      // Update cursor location and total line length.
      location++;
      line_length++;
    } else if ( ch == 10) {
      // <Enter> was typed. Return line
      
      // Print newline
      write(1, &ch, 1); 
      break;
    } else if (ch == 31) {
      // ctrl-?
      read_line_print_usage();
      line_buffer[0] = 0;
      break;
    } else if ((ch == 8 || ch == 127) && location > 0) {
      // <backspace> or CTRL-H was typed. Remove previous character read.
      ch = 8;
      write(1, &ch, 1);
      // If cursor is at the end of the line, simple deletion can be done.
      if (location == line_length) {
        // Write a space to erase the last character read
        ch = ' ';
        write(1,&ch,1);

        // Go back one character
        ch = 8;
        write(1,&ch,1);
      // Otherwise, overwrite the entire buffer back by one character,
      // updating the null terminator and shifting the cursor back to the 
      // correct position.
      } else {
        for (int i = 0; i < line_length - location; i++) {
	  write(1, &line_buffer[i + location], 1);
	  line_buffer[i + location - 1] = line_buffer[i + location];
	}
	ch = ' ';
	write(1, &ch, 1);
	line_buffer[line_length - 1] = '\0';
	for (int i = 0; i < line_length - location + 1; i++) {
	  ch = 8;
	  write(1, &ch, 1);
	}
      }
      // Update final location and remove one from total line length.
      line_length--;
      location--;
    } else if ((ch == 4) && location < line_length) {
      // CTRL-D - Delete Key
      // If at the end of the line, there is nothing to delete.
      // Otherwise, overwrite the rest of the buffer back by one character,
      // updating the null terminator and shifting the cursor back to the 
      // correct position.
      for (int i = 0; i < line_length - location; i++) {
        write(1, &line_buffer[i + location + 1], 1);
	line_buffer[i + location] = line_buffer[i + location + 1];
      }
      ch = ' ';
      write(1, &ch, 1);
      line_buffer[line_length] = '\0';
      for (int i = 0; i < line_length - location; i++) {
        ch = 8;
	write(1, &ch, 1);
      }
      // Remove one from total line length.
      line_length--;      
    } else if (ch == 1) {
      // Home/CTRL-A
      while (location > 0) {
        ch = 8;
	write(1,&ch,1);
	location--;
      } 
    } else if (ch == 5) {
      // End/CTRL-E
      while (location < line_length) {
	ch = line_buffer[location];
	write(1,&ch,1);
        location++;
      }
    } else if (ch == 27) {
      // Escape sequence. Read two chars more
      //
      // HINT: Use the program "keyboard-example" to
      // see the ascii code for the different chars typed.
      //
      char ch1; 
      char ch2;
      read(0, &ch1, 1);
      read(0, &ch2, 1);
      if (ch1 == 91 && ch2 == 65 && history_length > 0) {
	// Up arrow. Print next line in history.
  
	// Erase old line
	// Print backspaces
	int i = 0;
	for (i = 0; i < location; i++) {
	  ch = 8;
	  write(1,&ch,1);
	}

	// Print spaces on top
	for (i = 0; i < line_length; i++) {
	  ch = ' ';
	  write(1,&ch,1);
	}

	// Print backspaces
	for (int i = 0; i < line_length; i++) {
	  ch = 8;
	  write(1,&ch,1);
	}		

	// Copy line from history
	if (history[history_index][0] == '\n') {
	  strcpy(line_buffer, "");
	} else {
	  strcpy(line_buffer, history[history_index]);
	}

        history_index--;
	if (history_index < 0) history_index = history_length - 1;

	line_length = strlen(line_buffer);

	for (int i = 0; i < line_length; i++) {
	  ch = line_buffer[i];
          write(1, &ch, 1);
	}

	// Set cursor to the end of the line.
	location = line_length;
      } else if (ch1 == 91 && ch2 == 66 && history_length > 0) {
        // Down arrow. Print previous line in history.
        int i = 0;
	for (i = 0; i < location; i++) {
	  ch = 8;
	  write(1,&ch,1);
	}

	// Print spaces on top
	for (i = 0; i < line_length; i++) {
	  ch = ' ';
	  write(1,&ch,1);
	}

	// Print backspaces
	for (i = 0; i < line_length; i++) {
	  ch = 8;
	  write(1,&ch,1);
	}
        
	// Copy line from history
	history_index++;
        if (history_index > history_length - 1) history_index = 0;

        if (history[history_index][0] == '\n') {
	  strcpy(line_buffer, "");
	} else {
	  strcpy(line_buffer, history[history_index]);
	}

	line_length = strlen(line_buffer);
	       
        for (int i = 0; i < line_length; i++) {
	  ch = line_buffer[i];
	  write(1, &ch, 1);
	}

	// Update cursor to the end of the line.
	location = line_length;
      } else if (ch1 == 91 && ch2 == 68) {
        // Left arrow
	if (location > 0) {
	  ch = 8;
	  write(1,&ch,1);
	  location--;
	}
      } else if (ch1 == 91 && ch2 == 67) {
        // Right arrow
	if (location < line_length) {
	  ch = line_buffer[location];
	  write(1,&ch,1);
	  location++;
	}
      }
    }

  }
  
  // Add eol and null char at the end of string
  line_buffer[line_length] = 10;
  line_length++;
  line_buffer[line_length] = 0;
  
  // If the buffer is not empty, add an entry to the history table and adjust the null terminator amd
  // history length and index.
  if (strlen(line_buffer) != 0) {
    history[history_length] = (char *)malloc(strlen(line_buffer) * sizeof(char) + 1);
    strcpy(history[history_length], line_buffer);
    history[history_length][line_length - 1] = '\0';
    history_length++;
    history_index = history_length - 1;
  }

  // Call external function to reset terminal mode.
  tty_term_mode();

  // Pass processed line buffer to shell for lex/parsing.
  return line_buffer;
}
