⏱️ Todo Watchdog CLI - Simplified & Stable (v9)

This is a minimal, persistent, and distraction-free Pomodoro-style task manager designed exclusively for Linux terminal users. It ensures you never forget your tasks by running a silent daemon in the background that pops up a full-screen terminal reminder at set intervals until all todos are complete.

The primary focus of this version is stability and core functionality.

✨ Features

Autostart on Boot: Launches a full-screen terminal with your to-do list immediately upon logging in.

Background Daemon: After you exit the main session (using done or Ctrl+C), a silent background daemon starts running.

Time-Based Reminders: The daemon launches a full-screen reminder session at your specified interval (default is 25 minutes).

Persistent Storage: All todos, completion status, styling, and the reminder interval are saved persistently.

Two-Stage Alarm: When the reminder pops up, it plays a soft alarm, which escalates to an urgent alarm after 4 minutes if the session remains unacknowledged.

Advanced To-Do Management: Supports reordering, editing, deleting, and marking tasks as complete/incomplete.

Custom Styling: Allows setting text colors and toggling italics for individual tasks.

Robust Signal Handling: Captures Ctrl+C and terminal window closure signals to gracefully stop the foreground session and correctly launch the background daemon.

⚙️ Installation

Prerequisites

This script is designed for Ubuntu/Debian-based Linux distributions and requires gnome-terminal, wmctrl, and paplay (for sound).

Installation Steps

Save the Script: Save the full installation script provided as a file named install.sh (or similar).

To save: Type in terminal: 

sudo nano install.sh (or give any name, but use the same name for commands below too.) and hit enter to type your password. Then hit enter again.

Make Executable:

chmod +x install.sh


Run the Installer:

./install.sh


The script will handle installing dependencies, placing the main Python script in /usr/local/bin, and configuring the necessary autostart files.

Reboot (Required):
For the autostart and daemon processes to be correctly initialized by your desktop environment, you must reboot your system once:

sudo reboot (or reboot through GUI)


💻 Usage Commands

Once the Todo Watchdog launches, you interact with it entirely via the command-line interface.

Command

Example

Description

add <task name here. No quotes required>

add write report for Q4

Adds a new task to the list.

delete <index>

delete 2

Deletes the task at the specified index number.

edit <index> <new text>

edit 1 finish the proposal draft

Edits the text of an existing task.

complete <index>

complete 3

Marks the task at the index as ✓ completed.

incomplete <index>

incomplete 1

Marks a completed task back to ○ incomplete.

reorder <indices>

reorder 3,1,2

Reorders all tasks by specifying their new order. You can also reorder a subset, bringing those tasks to the front: reorder 10,7,2.

color <index> <color>

color 1 red

Sets the text color (e.g., red, blue, green, yellow, magenta, cyan, white, gray).

italic <index>

italic 5

Toggles italic formatting on/off for the task.

done or exit 

done

Closes the current terminal session and starts the background timer daemon. or ctrl+c can also be clicked for ease.

<number>

30

Sets the reminder interval (in minutes) for the daemon. Timer can only be changed when you intentionally log on to the app through terminal typing todo-watchdog and enter. In reminder sessions however, you can not change the timer.

help

help

Displays the list of available commands.

🏗️ Architecture & Daemon Function

The system relies on a two-part approach:

todo-watchdog.py (Main App): Handles all user interaction, CRUD operations, styling, and saving the data to ~/.local/share/todo-watchdog/todos.json.

daemon.sh (Background Timer): When the Python app exits via done or Ctrl+C, it launches the daemon.sh script into the background.

This script sits in a loop, sleeping for the configured interval.

When it wakes up, it checks if the reminder lock file exists (meaning a reminder is currently showing) or if there are any incomplete tasks.

If conditions are met, it launches a new full-screen terminal running todo-watchdog.py --reminder.

When the user exits the reminder session, the lock is released, and the daemon goes back to sleep.

This reliable signal-handling and daemon architecture guarantees that the timer remains running, regardless of whether the user intentionally closes the window or presses Ctrl+C.

Note: If all your todos are either completed or deleted, the daemon goes back to sleep. And you shall enter tasks either after fresh session is started or by manually launching the program in terminal. 


This is a friction program for your procrastinations.

<b> We believe each of your sessions are important. Every time you either restart your computer or log in to your desktop, you need to have certain intentions and todos to complete during the session. Now this daemon can better handle your procrastinatins. Have a great day. </b>
