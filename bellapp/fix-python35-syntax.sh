#!/bin/bash

# Fix Python 3.5 syntax errors in bellapp directory

echo "Fixing f-string syntax for Python 3.5 compatibility in bellapp..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Working directory: $SCRIPT_DIR"
echo "Project root: $PROJECT_ROOT"

# Fix vcns_timer_web.py in bellapp directory
echo "Fixing vcns_timer_web.py..."
if [ -f "$SCRIPT_DIR/vcns_timer_web.py" ]; then
    # Create backup
    cp "$SCRIPT_DIR/vcns_timer_web.py" "$SCRIPT_DIR/vcns_timer_web.py.backup.$(date +%Y%m%d_%H%M%S)"

    # Fix f-strings in vcns_timer_web.py
    sed -i 's/f"Failed to setup file logging: {e}"/("Failed to setup file logging: {}".format(e))/g' "$SCRIPT_DIR/vcns_timer_web.py"
    sed -i 's/logger\.error(f"Failed to setup file logging: {e}")/logger.error("Failed to setup file logging: {}".format(e))/g' "$SCRIPT_DIR/vcns_timer_web.py"

    # Fix any other common f-string patterns
    sed -i 's/f"Entering recovery mode after {self\.error_count} errors"/("Entering recovery mode after {} errors".format(self.error_count))/g' "$SCRIPT_DIR/vcns_timer_web.py"
    sed -i 's/f"Using UBUNTU_CONFIG_SERVICE_URL from environment: {ubuntu_config_service_base_url}"/("Using UBUNTU_CONFIG_SERVICE_URL from environment: {}".format(ubuntu_config_service_base_url))/g' "$SCRIPT_DIR/vcns_timer_web.py"

    echo "Fixed vcns_timer_web.py"
else
    echo "vcns_timer_web.py not found in $SCRIPT_DIR"
fi

# Fix ubuntu_config_service.py in project root
echo "Fixing ubuntu_config_service.py..."
if [ -f "$PROJECT_ROOT/ubuntu_config_service.py" ]; then
    # Create backup
    cp "$PROJECT_ROOT/ubuntu_config_service.py" "$PROJECT_ROOT/ubuntu_config_service.py.backup.$(date +%Y%m%d_%H%M%S)"

    # Fix f-strings in ubuntu_config_service.py
    sed -i 's/f"Executing command: {\x27 \x27\.join(command_list)}"/("Executing command: {}".format(\x27 \x27.join(command_list)))/g' "$PROJECT_ROOT/ubuntu_config_service.py"
    sed -i 's/logger\.info(f"Executing command: {\x27 \x27\.join(command_list)}")/logger.info("Executing command: {}".format(\x27 \x27.join(command_list)))/g' "$PROJECT_ROOT/ubuntu_config_service.py"
    sed -i 's/logger\.error(f"Command failed: {\x27 \x27\.join(command_list)}, Error: {e}")/logger.error("Command failed: {}, Error: {}".format(\x27 \x27.join(command_list), e))/g' "$PROJECT_ROOT/ubuntu_config_service.py"
    sed -i 's/logger\.error(f"Unexpected error: {e}")/logger.error("Unexpected error: {}".format(e))/g' "$PROJECT_ROOT/ubuntu_config_service.py"

    echo "Fixed ubuntu_config_service.py"
else
    echo "ubuntu_config_service.py not found in $PROJECT_ROOT"
fi

# More comprehensive Python-based fix
cat > /tmp/fix_all_fstrings.py << 'EOF'
import re
import sys
import os

def fix_fstrings_in_file(filename):
    if not os.path.exists(filename):
        print(f"File not found: {filename}")
        return False

    print(f"Processing {filename}...")

    with open(filename, 'r', encoding='utf-8') as f:
        content = f.read()

    original_content = content

    # Pattern 1: Simple f-strings with one variable
    pattern1 = r'f"([^"]*?)\{([^}]+?)\}([^"]*?)"'
    def replace1(match):
        before, var, after = match.groups()
        return f'"{before}{{}}{after}".format({var})'
    content = re.sub(pattern1, replace1, content)

    # Pattern 2: f-strings with two variables
    pattern2 = r'f"([^"]*?)\{([^}]+?)\}([^"]*?)\{([^}]+?)\}([^"]*?)"'
    def replace2(match):
        before, var1, middle, var2, after = match.groups()
        return f'"{before}{{}}{middle}{{}}{after}".format({var1}, {var2})'
    content = re.sub(pattern2, replace2, content)

    # Pattern 3: f-strings with three variables
    pattern3 = r'f"([^"]*?)\{([^}]+?)\}([^"]*?)\{([^}]+?)\}([^"]*?)\{([^}]+?)\}([^"]*?)"'
    def replace3(match):
        p1, v1, p2, v2, p3, v3, p4 = match.groups()
        return f'"{p1}{{}}{p2}{{}}{p3}{{}}{p4}".format({v1}, {v2}, {v3})'
    content = re.sub(pattern3, replace3, content)

    # Single quote f-strings
    pattern1_sq = r"f'([^']*?)\{([^}]+?)\}([^']*?)'"
    def replace1_sq(match):
        before, var, after = match.groups()
        return f"'{before}{{}}{after}'.format({var})"
    content = re.sub(pattern1_sq, replace1_sq, content)

    if content != original_content:
        with open(filename, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"Fixed f-strings in {filename}")
        return True
    else:
        print(f"No f-strings found in {filename}")
        return False

if __name__ == "__main__":
    files_fixed = 0
    for filename in sys.argv[1:]:
        if fix_fstrings_in_file(filename):
            files_fixed += 1
    print(f"Fixed {files_fixed} files")
EOF

# Run the comprehensive fix
python3 /tmp/fix_all_fstrings.py "$SCRIPT_DIR/vcns_timer_web.py" "$PROJECT_ROOT/ubuntu_config_service.py"

# Clean up
rm -f /tmp/fix_all_fstrings.py

echo ""
echo "✅ Syntax fixes completed!"
echo ""
echo "Now restarting services..."

# Stop services
sudo systemctl stop bellapp.service
sudo systemctl stop bellapp-config.service
sleep 2

# Start services
echo "Starting config service..."
sudo systemctl start bellapp-config.service
sleep 5

echo "Starting main bellapp service..."
sudo systemctl start bellapp.service
sleep 3

echo ""
echo "🔍 Checking service status..."
echo ""
echo "=== Config Service Status ==="
sudo systemctl status bellapp-config.service --no-pager -l
echo ""
echo "=== Main BellApp Status ==="
sudo systemctl status bellapp.service --no-pager -l

echo ""
echo "🌐 If services are running, access your BellApp at:"
echo "   http://$(hostname -I | awk '{print $1}'):5000"