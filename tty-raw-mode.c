
#include <stdlib.h>
#include <stdio.h>
#include <termios.h>
#include <string.h>

/* 
 * Sets terminal into raw mode. 
 * This causes having the characters available
 * immediately instead of waiting for a newline. 
 * Also there is no automatic echo.
 */

// Initialize termios to hold initial state
// of shell.
struct termios tty_attr;

// Set up and transfer shell into raw mode with
// new termios struct.
void tty_raw_mode(void) {

	struct termios new_attr;

	tcgetattr(0,&new_attr);
        tcgetattr(0,&tty_attr);

	/* Set raw mode. */
	new_attr.c_lflag &= (~(ICANON|ECHO));
	new_attr.c_cc[VTIME] = 0;
	new_attr.c_cc[VMIN] = 1;
     
	tcsetattr(0,TCSANOW,&new_attr);
}

// Return shell to previous state from original struct.
void tty_term_mode(void) {
        tcsetattr(0,TCSANOW,&tty_attr);
}
