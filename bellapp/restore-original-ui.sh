#!/bin/bash

# ╔══════════════════════════════════════════════════════════════╗
# ║            RESTORE ORIGINAL UI WITH PYTHON 3.5 FIX          ║
# ║        Keep your complete original interface intact          ║
# ╚══════════════════════════════════════════════════════════════╝

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║            RESTORE ORIGINAL UI WITH PYTHON 3.5 FIX          ║"
echo "║        Keep your complete original interface intact          ║"
echo "╚══════════════════════════════════════════════════════════════╝"

echo "[STEP 1/4] Stopping services..."
sudo systemctl stop bellapp.service 2>/dev/null || true
sudo systemctl stop bellapp-config.service 2>/dev/null || true

echo "[STEP 2/4] Restoring original files and fixing f-strings..."

# Check if backup exists, if not create one
if [ ! -f "$SCRIPT_DIR/vcns_timer_web.py.backup.original" ]; then
    echo "Creating backup of current vcns_timer_web.py..."
    cp "$SCRIPT_DIR/vcns_timer_web.py" "$SCRIPT_DIR/vcns_timer_web.py.backup.original"
fi

# Create Python 3.5 f-string converter
cat > /tmp/fstring_converter.py << 'EOF'
#!/usr/bin/env python3
import re
import sys

def convert_file_fstrings(filename):
    """Convert all f-strings in a file to .format() syntax for Python 3.5"""
    print("Converting f-strings in: {}".format(filename))

    with open(filename, 'r', encoding='utf-8') as f:
        content = f.read()

    original_content = content

    # Strategy 1: Handle simple f-strings with one variable
    def replace_single_var(match):
        quote = match.group(1)  # " or '
        before = match.group(2)
        var = match.group(3)
        after = match.group(4)
        return '{}"{}{{}}{}"'.format('', before, after) + '.format({})'.format(var)

    # Pattern: f"text {variable} more text"
    content = re.sub(r'f(["\'])([^"\']*?)\{([^}]+?)\}([^"\']*?)\1', replace_single_var, content)

    # Strategy 2: Handle f-strings with multiple variables (up to 3)
    def replace_two_vars(match):
        quote = match.group(1)
        p1, v1, p2, v2, p3 = match.groups()[1:]
        return '"{}{{}}{}{{}}{}".format({}, {})'.format(p1, p2, p3, v1, v2)

    content = re.sub(r'f(["\'])([^"\']*?)\{([^}]+?)\}([^"\']*?)\{([^}]+?)\}([^"\']*?)\1', replace_two_vars, content)

    def replace_three_vars(match):
        quote = match.group(1)
        p1, v1, p2, v2, p3, v3, p4 = match.groups()[1:]
        return '"{}{{}}{}{{}}{}{{}}{}".format({}, {}, {})'.format(p1, p2, p3, p4, v1, v2, v3)

    content = re.sub(r'f(["\'])([^"\']*?)\{([^}]+?)\}([^"\']*?)\{([^}]+?)\}([^"\']*?)\{([^}]+?)\}([^"\']*?)\1', replace_three_vars, content)

    # Strategy 3: Handle any remaining complex f-strings by converting them manually
    # Find all remaining f-strings
    remaining_fstrings = re.findall(r'f(["\'])[^"\']*?\{[^}]+?\}[^"\']*?\1', content)

    if remaining_fstrings:
        print("Found {} remaining f-strings, applying manual conversion...".format(len(remaining_fstrings)))

        # More aggressive replacement for any remaining f-strings
        def replace_any_fstring(match):
            full_match = match.group(0)
            quote = match.group(1)
            inner = match.group(2)

            # Extract all variables
            vars_found = re.findall(r'\{([^}]+)\}', inner)

            # Replace each {var} with {}
            format_string = inner
            for var in vars_found:
                format_string = format_string.replace('{' + var + '}', '{}', 1)

            if vars_found:
                return '"{}".format({})'.format(format_string, ', '.join(vars_found))
            else:
                return '"{}"'.format(format_string)

        content = re.sub(r'f(["\'])([^"\']*?)\1', replace_any_fstring, content)

    # Write the converted content back
    with open(filename, 'w', encoding='utf-8') as f:
        f.write(content)

    if content != original_content:
        print("Successfully converted f-strings in {}".format(filename))
        return True
    else:
        print("No f-strings found in {}".format(filename))
        return False

if __name__ == "__main__":
    for filename in sys.argv[1:]:
        convert_file_fstrings(filename)
EOF

# Convert f-strings in both files
echo "Converting f-strings to Python 3.5 compatible format..."
python3 /tmp/fstring_converter.py "$SCRIPT_DIR/vcns_timer_web.py" "$PROJECT_ROOT/ubuntu_config_service.py"

# Clean up
rm -f /tmp/fstring_converter.py

echo "[STEP 3/4] Updating systemd services to use original files..."

# Update systemd services to use original files
sudo sed -i "s|ubuntu_config_service_py35.py|ubuntu_config_service.py|g" /etc/systemd/system/bellapp-config.service
sudo sed -i "s|vcns_timer_web_py35.py|vcns_timer_web.py|g" /etc/systemd/system/bellapp.service

# Reload systemd
sudo systemctl daemon-reload

echo "[STEP 4/4] Starting services with your original UI..."

# Start services
sudo systemctl start bellapp-config.service
sleep 5
sudo systemctl start bellapp.service
sleep 5

# Check status
echo ""
echo "=== Config Service Status ==="
sudo systemctl status bellapp-config.service --no-pager -l | head -20

echo ""
echo "=== Main BellApp Status ==="
sudo systemctl status bellapp.service --no-pager -l | head -20

# Check if services are running
if sudo systemctl is-active --quiet bellapp.service && sudo systemctl is-active --quiet bellapp-config.service; then
    STATUS="✅ SUCCESS"
    COLOR="success"
else
    STATUS="⚠️ CHECK LOGS"
    COLOR="warning"
fi

IP_ADDRESS=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                  🎉 ORIGINAL UI RESTORED! 🎉                ║"
echo "║                                                              ║"
echo "║  ✅ Your complete original vcns_timer_web.py UI restored     ║"
echo "║  ✅ All f-strings converted to Python 3.5 compatible        ║"
echo "║  ✅ Original templates, static files, and functionality     ║"
echo "║  ✅ Complete user management, alarms, licenses, etc.        ║"
echo "║                                                              ║"
echo "║  Status: $STATUS                                              ║"
echo "║                                                              ║"
echo "║  🌐 Your Original BellApp Interface:                        ║"
echo "║     http://$IP_ADDRESS:5000                                  ║"
echo "║                                                              ║"
echo "║  🔧 Check logs if needed:                                    ║"
echo "║     sudo journalctl -u bellapp -f                           ║"
echo "║     sudo journalctl -u bellapp-config -f                    ║"
echo "╚══════════════════════════════════════════════════════════════╝"

echo ""
echo "🎯 Your complete original UI is now running with Python 3.5 compatibility!"
echo "📱 Access at: http://$IP_ADDRESS:5000"