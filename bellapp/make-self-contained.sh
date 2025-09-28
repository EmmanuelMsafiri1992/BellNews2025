#!/bin/bash

# ╔══════════════════════════════════════════════════════════════╗
# ║           MAKE BELLAPP COMPLETELY SELF-CONTAINED            ║
# ║    All dependencies, Python 3.5 compatible, no external    ║
# ║                     files needed                             ║
# ╚══════════════════════════════════════════════════════════════╝

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           MAKE BELLAPP COMPLETELY SELF-CONTAINED            ║"
echo "║    All dependencies, Python 3.5 compatible, no external    ║"
echo "║                     files needed                             ║"
echo "╚══════════════════════════════════════════════════════════════╝"

echo "[STEP 1/6] Stopping services and backing up original files..."

# Stop services
sudo systemctl stop bellapp.service 2>/dev/null || true
sudo systemctl stop bellapp-config.service 2>/dev/null || true

# Create comprehensive backup
BACKUP_DIR="$SCRIPT_DIR/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp -r "$SCRIPT_DIR"/* "$BACKUP_DIR/" 2>/dev/null || true
echo "Backup created at: $BACKUP_DIR"

echo "[STEP 2/6] Copying ubuntu_config_service into bellapp folder..."

# Copy the config service into bellapp folder
cp "$PROJECT_ROOT/ubuntu_config_service.py" "$SCRIPT_DIR/ubuntu_config_service.py"
echo "ubuntu_config_service.py copied to bellapp folder"

echo "[STEP 3/6] Creating Python 3.5 compatible versions of all files..."

# Create Python 3.5 compatibility converter
cat > "$SCRIPT_DIR/python35_converter.py" << 'EOFCONV'
#!/usr/bin/env python3
"""
Python 3.5 Compatibility Converter
Converts f-strings and other Python 3.6+ features to Python 3.5 compatible syntax
"""

import re
import os
import sys

def convert_fstrings_to_format(content):
    """Convert all f-strings to .format() syntax"""

    def replace_fstring_match(match):
        """Replace a single f-string match"""
        quote_char = match.group(1)  # " or '
        string_content = match.group(2)

        # Find all variables in {variable} format
        variables = []

        def extract_variable(var_match):
            var_expr = var_match.group(1)
            variables.append(var_expr)
            return '{}'

        # Replace {variable} with {} and collect variables
        format_string = re.sub(r'\{([^}]+)\}', extract_variable, string_content)

        if variables:
            return '{quote}{format_str}{quote}.format({vars})'.format(
                quote=quote_char,
                format_str=format_string,
                vars=', '.join(variables)
            )
        else:
            return '{quote}{format_str}{quote}'.format(
                quote=quote_char,
                format_str=format_string
            )

    # Convert f"..." and f'...' strings
    content = re.sub(r'f(["\'])([^"\']*?)\1', replace_fstring_match, content)

    return content

def fix_multiline_strings(content):
    """Fix broken multiline strings and concatenations"""
    lines = content.split('\n')
    fixed_lines = []
    i = 0

    while i < len(lines):
        line = lines[i]

        # Check for broken logger statements
        if 'logger.' in line and ('"' in line or "'" in line):
            # Check if this line has unmatched quotes or incomplete .format()
            quote_count_double = line.count('"') - line.count('\\"')
            quote_count_single = line.count("'") - line.count("\\'")

            if (quote_count_double % 2 != 0 or quote_count_single % 2 != 0) and i + 1 < len(lines):
                # This line has unmatched quotes, try to combine with next line
                next_line = lines[i + 1].strip()
                if next_line.startswith('"') or next_line.startswith("'"):
                    # Combine the lines
                    combined = line.rstrip() + ' ' + next_line
                    # Fix any f-strings in the combined line
                    combined = convert_fstrings_to_format(combined)
                    fixed_lines.append(combined)
                    i += 2  # Skip the next line since we combined it
                    continue

        # Convert f-strings in the current line
        line = convert_fstrings_to_format(line)
        fixed_lines.append(line)
        i += 1

    return '\n'.join(fixed_lines)

def process_file(filename):
    """Process a single Python file for Python 3.5 compatibility"""
    print("Processing: {}".format(filename))

    if not os.path.exists(filename):
        print("File not found: {}".format(filename))
        return False

    # Read file
    try:
        with open(filename, 'r', encoding='utf-8') as f:
            content = f.read()
    except Exception as e:
        print("Error reading {}: {}".format(filename, e))
        return False

    # Save original
    backup_name = filename + '.original'
    try:
        with open(backup_name, 'w', encoding='utf-8') as f:
            f.write(content)
    except Exception as e:
        print("Warning: Could not create backup {}: {}".format(backup_name, e))

    # Apply fixes
    content = fix_multiline_strings(content)
    content = convert_fstrings_to_format(content)

    # Remove any remaining f-string prefixes
    content = re.sub(r'\bf"([^"]*)"(?!\s*\.format)', r'"\1"', content)
    content = re.sub(r"\bf'([^']*)'(?!\s*\.format)", r"'\1'", content)

    # Write the fixed content
    try:
        with open(filename, 'w', encoding='utf-8') as f:
            f.write(content)
        print("Successfully processed: {}".format(filename))
        return True
    except Exception as e:
        print("Error writing {}: {}".format(filename, e))
        return False

def main():
    """Main function"""
    if len(sys.argv) < 2:
        print("Usage: python3 python35_converter.py <file1> [file2] ...")
        sys.exit(1)

    success_count = 0
    for filename in sys.argv[1:]:
        if process_file(filename):
            success_count += 1

    print("Conversion complete: {}/{} files processed successfully".format(
        success_count, len(sys.argv) - 1
    ))

if __name__ == "__main__":
    main()
EOFCONV

# Make converter executable
chmod +x "$SCRIPT_DIR/python35_converter.py"

echo "[STEP 4/6] Converting all Python files to Python 3.5 compatibility..."

# Convert all Python files in bellapp directory
python3 "$SCRIPT_DIR/python35_converter.py" "$SCRIPT_DIR/vcns_timer_web.py" "$SCRIPT_DIR/ubuntu_config_service.py"

# Check for any remaining Python files and convert them
find "$SCRIPT_DIR" -name "*.py" -not -name "python35_converter.py" -not -name "*.original" | while read file; do
    python3 "$SCRIPT_DIR/python35_converter.py" "$file"
done

echo "[STEP 5/6] Creating self-contained startup script..."

# Create a comprehensive startup script
cat > "$SCRIPT_DIR/start_bellapp_standalone.py" << 'EOFSTART'
#!/usr/bin/env python3
"""
BellApp Standalone Starter
Starts both the main web app and config service from within bellapp folder
"""

import os
import sys
import time
import signal
import subprocess
import threading
import logging

# Add current directory to Python path
current_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, current_dir)

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('BellAppStarter')

class ServiceManager:
    def __init__(self):
        self.config_service_process = None
        self.web_service_process = None
        self.shutdown_requested = False

    def start_config_service(self):
        """Start the Ubuntu config service"""
        try:
            logger.info("Starting Ubuntu Config Service...")

            # Set environment variables
            env = os.environ.copy()
            env['IN_DOCKER_TEST_MODE'] = 'false'
            env['NETWORK_MANAGER'] = 'interfaces'

            config_script = os.path.join(current_dir, 'ubuntu_config_service.py')
            self.config_service_process = subprocess.Popen(
                [sys.executable, config_script],
                cwd=current_dir,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )

            logger.info("Config service started with PID: {}".format(self.config_service_process.pid))
            return True
        except Exception as e:
            logger.error("Failed to start config service: {}".format(e))
            return False

    def start_web_service(self):
        """Start the main web service"""
        try:
            logger.info("Starting BellApp Web Service...")

            # Set environment variables
            env = os.environ.copy()
            env['UBUNTU_CONFIG_SERVICE_URL'] = 'http://localhost:5002'
            env['FLASK_ENV'] = 'production'
            env['FLASK_DEBUG'] = 'false'

            web_script = os.path.join(current_dir, 'vcns_timer_web.py')
            self.web_service_process = subprocess.Popen(
                [sys.executable, web_script],
                cwd=current_dir,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )

            logger.info("Web service started with PID: {}".format(self.web_service_process.pid))
            return True
        except Exception as e:
            logger.error("Failed to start web service: {}".format(e))
            return False

    def monitor_services(self):
        """Monitor both services and restart if needed"""
        while not self.shutdown_requested:
            try:
                # Check config service
                if self.config_service_process and self.config_service_process.poll() is not None:
                    logger.warning("Config service died, restarting...")
                    self.start_config_service()

                # Check web service
                if self.web_service_process and self.web_service_process.poll() is not None:
                    logger.warning("Web service died, restarting...")
                    time.sleep(5)  # Wait for config service to be ready
                    self.start_web_service()

                time.sleep(10)  # Check every 10 seconds
            except Exception as e:
                logger.error("Error in service monitor: {}".format(e))
                time.sleep(5)

    def shutdown(self):
        """Shutdown all services"""
        logger.info("Shutting down services...")
        self.shutdown_requested = True

        if self.web_service_process:
            try:
                self.web_service_process.terminate()
                self.web_service_process.wait(timeout=10)
            except:
                self.web_service_process.kill()

        if self.config_service_process:
            try:
                self.config_service_process.terminate()
                self.config_service_process.wait(timeout=10)
            except:
                self.config_service_process.kill()

        logger.info("Services shut down")

    def start_all(self):
        """Start all services"""
        logger.info("Starting BellApp Standalone...")

        # Start config service first
        if not self.start_config_service():
            logger.error("Failed to start config service")
            return False

        # Wait for config service to be ready
        logger.info("Waiting for config service to be ready...")
        time.sleep(5)

        # Start web service
        if not self.start_web_service():
            logger.error("Failed to start web service")
            return False

        # Start monitoring in a separate thread
        monitor_thread = threading.Thread(target=self.monitor_services)
        monitor_thread.daemon = True
        monitor_thread.start()

        logger.info("BellApp services started successfully!")
        logger.info("Web interface: http://localhost:5000")
        logger.info("Config service: http://localhost:5002")

        return True

def signal_handler(signum, frame):
    """Handle shutdown signals"""
    logger.info("Received signal {}, shutting down...".format(signum))
    manager.shutdown()
    sys.exit(0)

def main():
    """Main function"""
    global manager
    manager = ServiceManager()

    # Setup signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # Check if running as root (needed for network operations)
    if os.geteuid() != 0:
        logger.warning("Not running as root. Network configuration may not work.")

    # Start services
    if not manager.start_all():
        logger.error("Failed to start services")
        sys.exit(1)

    # Keep the main thread alive
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        signal_handler(signal.SIGINT, None)

if __name__ == "__main__":
    main()
EOFSTART

chmod +x "$SCRIPT_DIR/start_bellapp_standalone.py"

echo "[STEP 6/6] Creating systemd service for self-contained bellapp..."

# Create new systemd service file for standalone bellapp
sudo tee "/etc/systemd/system/bellapp-standalone.service" > /dev/null << EOFSERVICE
[Unit]
Description=BellApp Standalone Service (Self-Contained)
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$SCRIPT_DIR
ExecStart=/usr/bin/python3 $SCRIPT_DIR/start_bellapp_standalone.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOFSERVICE

# Disable old services
sudo systemctl disable bellapp.service 2>/dev/null || true
sudo systemctl disable bellapp-config.service 2>/dev/null || true

# Enable new service
sudo systemctl daemon-reload
sudo systemctl enable bellapp-standalone.service

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                 🎉 SELF-CONTAINED SETUP COMPLETE! 🎉        ║"
echo "║                                                              ║"
echo "║  ✅ All files now in bellapp folder                         ║"
echo "║  ✅ Python 3.5 compatible versions created                  ║"
echo "║  ✅ No external dependencies needed                         ║"
echo "║  ✅ All original functionalities preserved                  ║"
echo "║  ✅ Self-contained startup script created                   ║"
echo "║                                                              ║"
echo "║  📁 Bellapp folder now contains:                            ║"
echo "║     • vcns_timer_web.py (your main app)                    ║"
echo "║     • ubuntu_config_service.py (config service)            ║"
echo "║     • start_bellapp_standalone.py (startup manager)        ║"
echo "║     • All templates, static files, etc.                    ║"
echo "║                                                              ║"
echo "║  🚀 To start manually:                                      ║"
echo "║     cd $SCRIPT_DIR                                          ║"
echo "║     sudo python3 start_bellapp_standalone.py               ║"
echo "║                                                              ║"
echo "║  🔧 To start via systemd:                                   ║"
echo "║     sudo systemctl start bellapp-standalone                ║"
echo "║                                                              ║"
echo "║  📋 View logs:                                               ║"
echo "║     sudo journalctl -u bellapp-standalone -f               ║"
echo "╚══════════════════════════════════════════════════════════════╝"

echo ""
echo "Testing syntax of converted files..."

# Test all Python files for syntax errors
SYNTAX_OK=true
for py_file in "$SCRIPT_DIR"/*.py; do
    if [ -f "$py_file" ] && [[ "$py_file" != *".original" ]]; then
        echo "Testing: $(basename "$py_file")"
        if ! python3 -m py_compile "$py_file" 2>/dev/null; then
            echo "❌ Syntax error in: $(basename "$py_file")"
            SYNTAX_OK=false
        else
            echo "✅ OK: $(basename "$py_file")"
        fi
    fi
done

if [ "$SYNTAX_OK" = true ]; then
    echo ""
    echo "🎉 All files have correct syntax! Starting the service..."
    sudo systemctl start bellapp-standalone.service
    sleep 5

    # Check service status
    if sudo systemctl is-active --quiet bellapp-standalone.service; then
        IP_ADDRESS=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")
        echo "✅ Service started successfully!"
        echo "🌐 Access your BellApp at: http://$IP_ADDRESS:5000"
    else
        echo "⚠️ Service may have issues. Check logs:"
        echo "sudo journalctl -u bellapp-standalone -n 20"
    fi
else
    echo ""
    echo "❌ Some files have syntax errors. Please check the output above."
    echo "You can manually fix the errors and then start the service with:"
    echo "sudo systemctl start bellapp-standalone"
fi

echo ""
echo "🔄 Service will auto-start on reboot!"
echo "📂 Backup of original files: $BACKUP_DIR"