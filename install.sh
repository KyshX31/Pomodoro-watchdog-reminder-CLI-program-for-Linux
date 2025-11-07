#!/bin/bash

echo "Installing Simplified & Stable Todo Watchdog (v9)..."

# Install required packages (REMOVED python3-tk)
echo "Installing dependencies..."
sudo apt-get update -qq 2>&1 | grep -v "^Get:"
sudo apt-get install -y wmctrl paplay 2>&1 | grep -v "^Selecting\|^Preparing\|^Unpacking"

echo "✓ Dependencies installed"

# Create the main Python script
cat > /tmp/todo-watchdog.py << 'PYTHON_SCRIPT'
#!/usr/bin/env python3
"""
Todo Watchdog - Simplified & Stable Edition (v9)
Features: autostart, daemon, terminal reminders, reorder, color, italic
"""

import os
import sys
import json
import time
import subprocess
import signal
import atexit
from pathlib import Path
from datetime import datetime
import threading

# Store data in ~/.local/share/todo-watchdog/
DATA_DIR = Path.home() / ".local" / "share" / "todo-watchdog"
TODO_FILE = DATA_DIR / "todos.json"
CONFIG_FILE = DATA_DIR / "config.json"
DAEMON_PID_FILE = DATA_DIR / "daemon.pid"
LOCK_FILE = DATA_DIR / "reminder.lock"
LAST_ACTIVE_FILE = DATA_DIR / "last_active.txt"

DEFAULT_INTERVAL = 25  # Pomodoro standard

# ============================================================================
# SOUND CONFIGURATION
# ============================================================================
SOFT_ALARM = "/usr/share/sounds/freedesktop/stereo/complete.oga"
URGENT_ALARM = "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"
ALARM_SWITCH_SECONDS = 270  # 4 minutes
# ============================================================================

# ============================================================================
# UI CUSTOMIZATION
# ============================================================================
INDEX_COLOR = "\033[36m"        # Cyan
SUCCESS_COLOR = "\033[32m"      # Green
ERROR_COLOR = "\033[31m"        # Red
WARNING_COLOR = "\033[33m"      # Yellow
RESET_COLOR = "\033[0m"
# ============================================================================

class TodoWatchdog:
    def __init__(self):
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        self.todos = self.load_todos()
        self.config = self.load_config()
        self.beeping = False
        self.alarm_start_time = None
        
        # Detect session type
        self.is_reminder_session = '--reminder' in sys.argv
        self.daemon_should_start = False
        
        # Catch ALL exit signals
        atexit.register(self.cleanup_on_exit)
        signal.signal(signal.SIGTERM, self.handle_signal)
        signal.signal(signal.SIGHUP, self.handle_signal)
        signal.signal(signal.SIGINT, self.handle_signal)
        
    def cleanup_on_exit(self):
        """Smart cleanup with race condition fix"""
        self.stop_alert()
        
        if self.is_reminder_session:
            if LOCK_FILE.exists():
                try:
                    LOCK_FILE.unlink()
                except:
                    pass
        else:
            if LOCK_FILE.exists():
                try:
                    LOCK_FILE.unlink()
                except:
                    pass
            
            if self.daemon_should_start and self.has_incomplete_todos():
                time.sleep(0.8)
                self.start_daemon()
    
    def handle_signal(self, signum, frame):
        """Handle termination signals"""
        if not self.is_reminder_session:
            self.daemon_should_start = True
        sys.exit(0)
        
    def load_todos(self):
        if TODO_FILE.exists():
            try:
                with open(TODO_FILE, 'r') as f:
                    data = json.load(f)
                    # Ensure todos have styling info
                    for todo in data:
                        if 'color' not in todo:
                            todo['color'] = None
                        if 'italic' not in todo:
                            todo['italic'] = False
                    return data
            except json.JSONDecodeError:
                return []
        return []
    
    def save_todos(self):
        with open(TODO_FILE, 'w') as f:
            json.dump(self.todos, f, indent=2)
    
    def load_config(self):
        if CONFIG_FILE.exists():
            try:
                with open(CONFIG_FILE, 'r') as f:
                    return json.load(f)
            except json.JSONDecodeError:
                return {'interval': DEFAULT_INTERVAL}
        return {'interval': DEFAULT_INTERVAL}
    
    def save_config(self):
        with open(CONFIG_FILE, 'w') as f:
            json.dump(self.config, f, indent=2)
    
    def get_interval(self):
        return self.config.get('interval', DEFAULT_INTERVAL)
    
    def set_interval(self, interval):
        self.config['interval'] = interval
        self.save_config()
    
    def update_last_active(self):
        """Update the last active timestamp"""
        with open(LAST_ACTIVE_FILE, 'w') as f:
            f.write(str(int(time.time())))
    
    def get_color_code(self, color_name):
        """Convert color name/hex to ANSI code"""
        if not color_name:
            return '\033[97m'  # default white
        
        color_map = {
            'red': '\033[91m',
            'green': '\033[92m',
            'yellow': '\033[93m',
            'blue': '\033[94m',
            'magenta': '\033[95m',
            'cyan': '\033[96m',
            'white': '\033[97m',
            'gray': '\033[90m',
        }
        return color_map.get(color_name.lower(), '\033[97m')
    
    def display_todos(self):
        """Display todos with custom styling"""
        print("\n" + "="*60)
        print("YOUR TODOS:")
        print("="*60)
        
        if not self.todos:
            print("  (No todos yet - all clear!)")
        else:
            for i, todo in enumerate(self.todos, 1):
                completed = todo.get('completed', False)
                text = todo['text']
                
                # Apply styling
                color_code = self.get_color_code(todo.get('color'))
                italic_code = '\033[3m' if todo.get('italic', False) else ''
                
                # Status emoji - smaller and aligned
                status = "✓" if completed else "○"
                
                # Build the line
                line = f"  {INDEX_COLOR}{i}.{RESET_COLOR} {color_code}{italic_code}[{status}] {text}{RESET_COLOR}"
                print(line)
        
        print("="*60 + "\n")
    
    def add_todo(self, text):
        self.todos.append({
            'text': text, 
            'completed': False,
            'color': None,
            'italic': False
        })
        self.save_todos()
        print(f"{SUCCESS_COLOR}✓ Added:{RESET_COLOR} {text}")
    
    def delete_todo(self, index):
        if 1 <= index <= len(self.todos):
            removed = self.todos.pop(index - 1)
            self.save_todos()
            print(f"{SUCCESS_COLOR}✓ Deleted:{RESET_COLOR} {removed['text']}")
            return True
        else:
            print(f"{ERROR_COLOR}✗ Invalid index: {index}{RESET_COLOR}")
            return False
    
    def edit_todo(self, index, new_text):
        if 1 <= index <= len(self.todos):
            self.todos[index - 1]['text'] = new_text
            self.save_todos()
            print(f"{SUCCESS_COLOR}✓ Edited todo #{index}{RESET_COLOR}")
            return True
        else:
            print(f"{ERROR_COLOR}✗ Invalid index: {index}{RESET_COLOR}")
            return False
    
    def reorder_todos(self, order_string):
        """Reorder todos - supports partial reordering with commas"""
        try:
            # Remove spaces and split by comma
            indices = [int(x.strip()) for x in order_string.replace(' ', '').split(',') if x.strip()]
            
            if not indices:
                print(f"{ERROR_COLOR}✗ No indices provided{RESET_COLOR}")
                return False
            
            # Check if all indices are valid
            for idx in indices:
                if idx < 1 or idx > len(self.todos):
                    print(f"{ERROR_COLOR}✗ Invalid index: {idx} (must be 1-{len(self.todos)}){RESET_COLOR}")
                    return False
            
            # Check for duplicates
            if len(indices) != len(set(indices)):
                print(f"{ERROR_COLOR}✗ Duplicate indices not allowed{RESET_COLOR}")
                return False
            
            # Full reorder (all todos specified)
            if len(indices) == len(self.todos):
                new_order = [self.todos[i-1] for i in indices]
                self.todos = new_order
            else:
                # Partial reorder
                moved_todos = [self.todos[i-1] for i in indices]
                remaining_indices = [i for i in range(1, len(self.todos)+1) if i not in indices]
                remaining_todos = [self.todos[i-1] for i in remaining_indices]
                self.todos = moved_todos + remaining_todos
            
            self.save_todos()
            print(f"{SUCCESS_COLOR}✓ Todos reordered{RESET_COLOR}")
            self.display_todos()
            return True
        except ValueError:
            print(f"{ERROR_COLOR}✗ Invalid format. Use: reorder 3,2,1 or reorder 10,7,2{RESET_COLOR}")
            return False
    
    def set_todo_color(self, index, color):
        """Set color for a todo"""
        if 1 <= index <= len(self.todos):
            self.todos[index - 1]['color'] = color
            self.save_todos()
            print(f"{SUCCESS_COLOR}✓ Set todo #{index} color to {color}{RESET_COLOR}")
            return True
        else:
            print(f"{ERROR_COLOR}✗ Invalid index: {index}{RESET_COLOR}")
            return False
    
    def set_todo_italic(self, index):
        """Toggle italic for a todo"""
        if 1 <= index <= len(self.todos):
            current = self.todos[index - 1].get('italic', False)
            self.todos[index - 1]['italic'] = not current
            self.save_todos()
            status = "enabled" if not current else "disabled"
            print(f"{SUCCESS_COLOR}✓ Italic {status} for todo #{index}{RESET_COLOR}")
            return True
        else:
            print(f"{ERROR_COLOR}✗ Invalid index: {index}{RESET_COLOR}")
            return False
    
    def complete_todo(self, index):
        if 1 <= index <= len(self.todos):
            self.todos[index - 1]['completed'] = True
            self.save_todos()
            print(f"{SUCCESS_COLOR}✓ Completed:{RESET_COLOR} {self.todos[index - 1]['text']}")
            return True
        else:
            print(f"{ERROR_COLOR}✗ Invalid index: {index}{RESET_COLOR}")
            return False
    
    def incomplete_todo(self, index):
        """Mark todo as incomplete"""
        if 1 <= index <= len(self.todos):
            self.todos[index - 1]['completed'] = False
            self.save_todos()
            print(f"{SUCCESS_COLOR}✓ Marked incomplete:{RESET_COLOR} {self.todos[index - 1]['text']}")
            return True
        else:
            print(f"{ERROR_COLOR}✗ Invalid index: {index}{RESET_COLOR}")
            return False
    
    def has_incomplete_todos(self):
        return any(not todo.get('completed', False) for todo in self.todos)
    
    def play_alert(self):
        """Play two-stage alarm system"""
        self.beeping = True
        self.alarm_start_time = time.time()
        
        def beep_loop():
            while self.beeping:
                elapsed = time.time() - self.alarm_start_time
                
                # Choose alarm based on elapsed time
                if elapsed < ALARM_SWITCH_SECONDS:
                    alarm_sound = SOFT_ALARM
                else:
                    alarm_sound = URGENT_ALARM
                
                try:
                    subprocess.run(['paplay', alarm_sound], 
                                   stderr=subprocess.DEVNULL, 
                                   stdout=subprocess.DEVNULL,
                                   timeout=2)
                except:
                    print('\a', end='', flush=True)
                
                time.sleep(2)
        
        self.beep_thread = threading.Thread(target=beep_loop, daemon=True)
        self.beep_thread.start()
    
    def stop_alert(self):
        self.beeping = False
        self.alarm_start_time = None
    
    def clear_screen(self):
        os.system('clear')
    
    def parse_command(self, cmd):
        """Parse user command"""
        parts = cmd.strip().split(maxsplit=1)
        if not parts:
            return None, None, None
        
        command = parts[0].lower()
        
        if command.isdigit():
            return 'interval', int(command), None
        
        if command == 'add' and len(parts) > 1:
            return 'add', parts[1], None
        elif command == 'delete' and len(parts) > 1:
            try:
                return 'delete', int(parts[1]), None
            except ValueError:
                return 'error', 'Invalid index for delete', None
        elif command == 'edit' and len(parts) > 1:
            edit_parts = parts[1].split(maxsplit=1)
            if len(edit_parts) == 2:
                try:
                    return 'edit', int(edit_parts[0]), edit_parts[1]
                except ValueError:
                    return 'error', 'Invalid index for edit', None
            return 'error', 'Usage: edit <index> <new text>', None
        elif command == 'reorder' and len(parts) > 1:
            return 'reorder', parts[1], None
        elif command == 'complete' and len(parts) > 1:
            try:
                return 'complete', int(parts[1]), None
            except ValueError:
                return 'error', 'Invalid index for complete', None
        elif command == 'incomplete' and len(parts) > 1:
            try:
                return 'incomplete', int(parts[1]), None
            except ValueError:
                return 'error', 'Invalid index for incomplete', None
        elif command == 'color' and len(parts) > 1:
            color_parts = parts[1].split(maxsplit=1)
            if len(color_parts) == 2:
                try:
                    return 'color', int(color_parts[0]), color_parts[1]
                except ValueError:
                    return 'error', 'Usage: color <index> <color>', None
            return 'error', 'Usage: color <index> <color>', None
        elif command == 'italic' and len(parts) > 1:
            try:
                return 'italic', int(parts[1]), None
            except ValueError:
                return 'error', 'Invalid index for italic', None
        elif command in ['exit', 'quit', 'done']:
            return command, None, None
        elif command == 'help':
            return 'help', None, None
        else:
            return 'error', f'Unknown command: {command}', None
    
    def show_help(self, allow_timer_change=True):
        print("\n" + "="*60)
        print("AVAILABLE COMMANDS:")
        print("="*60)
        print("\n📝 TASK MANAGEMENT:")
        print("  add <task>          - Add a new todo")
        print("  delete <index>      - Delete a todo")
        print("  edit <index> <text> - Edit a todo")
        print("  reorder <indices>   - Reorder todos")
        print("                        Full: reorder 3,2,1")
        print("                        Partial: reorder 10,7,2")
        
        print("\n✅ STATUS:")
        print("  complete <index>    - Mark todo as complete")
        print("  incomplete <index>  - Mark todo as incomplete")
        
        print("\n🎨 STYLING:")
        print("  color <index> <col> - Set color (red/blue/green/yellow/etc)")
        print("  italic <index>      - Toggle italic formatting")
        
        if allow_timer_change:
            print("\n⏱️  TIMER:")
            print("  <number>            - Set reminder interval in minutes")
        
        print("\n🚪 EXIT:")
        print("  done                - Close window & start Pomodoro timer")
        print("  (Ctrl+C also works)")
        print("="*60 + "\n")
    
    def interactive_session(self, is_initial=False, is_reminder=False):
        """Main interactive session"""
        self.clear_screen()
        
        allow_timer_change = is_initial or (not is_reminder and '--autostart' not in sys.argv)
        
        if is_reminder or is_initial:
            try:
                subprocess.run(['wmctrl', '-r', ':ACTIVE:', '-b', 'add,fullscreen'], 
                               stderr=subprocess.DEVNULL)
            except:
                pass
        
        if is_reminder:
            print("\n" + "="*60)
            print(" ⏰ TODO WATCHDOG REMINDER ⏰")
            print("="*60)
            print("\nWhich tasks are complete?\n")
            self.play_alert()
        else:
            print("\n" + "="*60)
            if is_initial:
                print(" TODO WATCHDOG - Session Started")
            else:
                print(" TODO WATCHDOG")
            print("="*60)
            if is_initial:
                print("\nWhat are your intentions for this session?")
            print()
        
        self.display_todos()
        
        current_interval = self.get_interval()
        print(f"Current reminder interval: {current_interval} minutes")
        if allow_timer_change:
            print("(Enter a number to change it)")
        else:
            print(f"{WARNING_COLOR}(Timer locked during reminders){RESET_COLOR}")
        
        print("\nType 'help' for all commands\n")
        
        first_input = True
        
        while True:
            try:
                user_input = input("todo> ").strip()
                
                if is_reminder and first_input:
                    self.stop_alert()
                    first_input = False
                
                if not user_input:
                    continue
                
                cmd, arg1, arg2 = self.parse_command(user_input)
                
                if cmd == 'add':
                    self.add_todo(arg1)
                    self.display_todos()
                elif cmd == 'delete':
                    self.delete_todo(arg1)
                    self.display_todos()
                elif cmd == 'edit':
                    self.edit_todo(arg1, arg2)
                    self.display_todos()
                elif cmd == 'reorder':
                    self.reorder_todos(arg1)
                elif cmd == 'complete':
                    self.complete_todo(arg1)
                    self.display_todos()
                elif cmd == 'incomplete':
                    self.incomplete_todo(arg1)
                    self.display_todos()
                elif cmd == 'color':
                    self.set_todo_color(arg1, arg2)
                    self.display_todos()
                elif cmd == 'italic':
                    self.set_todo_italic(arg1)
                    self.display_todos()
                elif cmd == 'interval':
                    if allow_timer_change:
                        self.set_interval(arg1)
                        print(f"\n{SUCCESS_COLOR}✓ Reminder interval set to {arg1} minutes{RESET_COLOR}\n")
                    else:
                        print(f"\n{WARNING_COLOR}✗ Timer locked during reminders{RESET_COLOR}\n")
                elif cmd == 'help':
                    self.show_help(allow_timer_change)
                elif cmd in ['done', 'exit', 'quit']:
                    if is_reminder:
                        self.stop_alert()
                    else:
                        self.daemon_should_start = True
                    print("\nClosing...\n")
                    return
                elif cmd == 'error':
                    print(f"{ERROR_COLOR}✗ {arg1}{RESET_COLOR}")
            
            except (KeyboardInterrupt, EOFError):
                if is_reminder:
                    self.stop_alert()
                else:
                    self.daemon_should_start = True
                print("\nClosing...\n")
                return
    
    def kill_existing_daemon(self):
        """Kill any existing daemon"""
        if DAEMON_PID_FILE.exists():
            try:
                with open(DAEMON_PID_FILE, 'r') as f:
                    old_pid = int(f.read().strip())
                os.kill(old_pid, signal.SIGTERM)
                time.sleep(0.5)
            except (ProcessLookupError, ValueError, FileNotFoundError):
                pass
            try:
                DAEMON_PID_FILE.unlink()
            except:
                pass
    
    def start_daemon(self):
        """Start the reminder daemon"""
        if not self.has_incomplete_todos():
            return
        
        self.kill_existing_daemon()
        
        interval = self.get_interval()
        script_path = Path(sys.argv[0]).resolve()
        
        if not script_path.exists():
            print(f"{ERROR_COLOR}ERROR: Could not find script at {script_path}{RESET_COLOR}")
            return

        daemon_script = f'''#!/bin/bash
echo $$ > {DAEMON_PID_FILE}

while true; do
    sleep {interval * 60}
    
    # Check for incomplete todos
    HAS_INCOMPLETE=$(python3 -c "import json, sys, os; f = '{TODO_FILE}'; print(os.path.exists(f) and any(not t.get('completed',False) for t in json.load(open(f))))" 2>/dev/null)
    
    if [ "$HAS_INCOMPLETE" != "True" ]; then
        rm -f {DAEMON_PID_FILE}
        rm -f {LOCK_FILE}
        exit 0
    fi
    
    if [ -f {LOCK_FILE} ]; then
        continue
    fi
    
    touch {LOCK_FILE}
    
    # Launch reminder
    gnome-terminal --full-screen --hide-menubar -- python3 {script_path} --reminder
    
    # Wait for lock removal
    while [ -f {LOCK_FILE} ]; do
        sleep 1
    done
    
    sleep 1
done
'''
        
        daemon_file = DATA_DIR / "daemon.sh"
        with open(daemon_file, 'w') as f:
            f.write(daemon_script)
        os.chmod(daemon_file, 0o755)
        
        subprocess.Popen(['bash', str(daemon_file)], 
                         start_new_session=True, 
                         stdout=subprocess.DEVNULL, 
                         stderr=subprocess.DEVNULL)
        
        print(f"{SUCCESS_COLOR}✓ Watchdog daemon started (reminders every {interval} minutes){RESET_COLOR}")

def main():
    watchdog = TodoWatchdog()
    
    is_reminder = watchdog.is_reminder_session
    
    if is_reminder:
        with open(LOCK_FILE, 'w') as f:
            f.write(str(os.getpid()))
    
    is_initial = not CONFIG_FILE.exists()
    watchdog.update_last_active()
    
    if is_reminder:
        if watchdog.has_incomplete_todos():
            watchdog.interactive_session(is_initial=False, is_reminder=True)
    else:
        watchdog.interactive_session(is_initial=is_initial, is_reminder=False)

if __name__ == '__main__':
    main()
PYTHON_SCRIPT

# Install the Python script
sudo mkdir -p /usr/local/bin
sudo mv /tmp/todo-watchdog.py /usr/local/bin/todo-watchdog
sudo chmod +x /usr/local/bin/todo-watchdog

echo "✓ Main script installed"

# Create autostart for main app
mkdir -p ~/.config/autostart

cat > ~/.config/autostart/todo-watchdog.desktop << 'AUTOSTART1'
[Desktop Entry]
Type=Application
Name=Todo Watchdog
Exec=gnome-terminal --full-screen --hide-menubar -- /usr/local/bin/todo-watchdog
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
StartupNotify=false
AUTOSTART1

echo "✓ Main app autostart configured"

# Create logout script
cat > /tmp/logout-check.sh << 'LOGOUT_SCRIPT'
#!/bin/bash
DAEMON_PID="$HOME/.local/share/todo-watchdog/daemon.pid"
LOCK_FILE="$HOME/.local/share/todo-watchdog/reminder.lock"

if [ -f "$DAEMON_PID" ]; then
    kill $(cat "$DAEMON_PID") 2>/dev/null
    rm -f "$DAEMON_PID"
fi

rm -f "$LOCK_FILE"

exit 0
LOGOUT_SCRIPT

sudo mv /tmp/logout-check.sh /usr/local/bin/todo-watchdog-logout
sudo chmod +x /usr/local/bin/todo-watchdog-logout

echo "✓ Logout script installed"

echo ""
echo "============================================"
echo " TODO WATCHDOG - SIMPLIFIED & STABLE (v9)"
echo "============================================"
echo ""
echo "✅ CHANGES MADE (AS REQUESTED):"
echo "  ✓ REMOVED: All overlay timer logic."
echo "  ✓ REMOVED: All 'size' command logic."
echo "  ✓ REMOVED: All suspend/resume logic."
echo ""
echo "🎨 CORE FEATURES (PRESERVED):"
echo "  🔔 Autostart on boot (full-screen terminal)."
echo "  🔔 Background daemon for reminders."
echo "  🔔 Two-stage alarm (soft → urgent)."
echo "  📋 Todo reordering with commas (reorder 10,7,2)."
echo "  🎨 Custom styling ('color' and 'italic')."
echo "  ✅ 'complete' / 'incomplete' commands."
echo "  ✅ Signal handling (Ctrl+C / 'done') works."
echo ""
echo "🧪 TESTING:"
echo ""
echo "1. TEST AUTOSTART:"
echo "   sudo reboot"
echo "   → Terminal should popup fullscreen."
echo ""
echo "2. TEST DAEMON (THE REAL TEST):"
echo "   - In the terminal, add a todo: add 'Test'"
echo "   - Set a 1-minute timer: 1"
echo "   - Close the window using: done (or press Ctrl+C)"
echo ""
echo "3. TEST ALARM:"
echo "   - Wait 1 minute."
echo "   - The terminal reminder will pop up."
echo "   - You should hear the alarm."
echo "   - Type: done"
echo "   → The daemon will start again for the next reminder."
echo ""
echo "🎉 INSTALLATION COMPLETE!"
echo "   Please RESTART your computer to test."
echo ""

# Launch the app immediately for first-time use
echo "Launching Todo Watchdog for first-time setup..."
gnome-terminal --full-screen --hide-menubar -- /usr/local/bin/todo-watchdog &
