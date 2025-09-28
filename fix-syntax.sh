#!/bin/bash

# Fix Python 3.5 syntax errors in both files

echo "Fixing f-string syntax for Python 3.5 compatibility..."

# Fix ubuntu_config_service.py
echo "Fixing ubuntu_config_service.py..."
sed -i 's/logger\.info(f"Executing command: {\x27 \x27\.join(command_list)}")/logger.info("Executing command: {}".format(\x27 \x27.join(command_list)))/g' /root/BellNews2025/ubuntu_config_service.py
sed -i 's/logger\.error(f"Command failed: {\x27 \x27\.join(command_list)}, Error: {e}")/logger.error("Command failed: {}, Error: {}".format(\x27 \x27.join(command_list), e))/g' /root/BellNews2025/ubuntu_config_service.py
sed -i 's/logger\.error(f"Unexpected error: {e}")/logger.error("Unexpected error: {}".format(e))/g' /root/BellNews2025/ubuntu_config_service.py
sed -i 's/logger\.info(f"Output: {output}")/logger.info("Output: {}".format(output))/g' /root/BellNews2025/ubuntu_config_service.py
sed -i 's/logger\.warning(f"Command failed: {\x27 \x27\.join(command_list)}, Error: {e}")/logger.warning("Command failed: {}, Error: {}".format(\x27 \x27.join(command_list), e))/g' /root/BellNews2025/ubuntu_config_service.py

# More comprehensive fix using Python
cat > /tmp/fix_fstrings.py << 'EOF'
import re
import sys

def fix_file(filename):
    print(f"Fixing {filename}...")

    with open(filename, 'r') as f:
        content = f.read()

    # Common f-string patterns and their replacements
    replacements = [
        # logger.info(f"text {var}")
        (r'logger\.info\(f"([^"]*)\{([^}]+)\}([^"]*)"\)', r'logger.info("\1{}\3".format(\2))'),
        (r'logger\.error\(f"([^"]*)\{([^}]+)\}([^"]*)"\)', r'logger.error("\1{}\3".format(\2))'),
        (r'logger\.warning\(f"([^"]*)\{([^}]+)\}([^"]*)"\)', r'logger.warning("\1{}\3".format(\2))'),
        (r'logger\.debug\(f"([^"]*)\{([^}]+)\}([^"]*)"\)', r'logger.debug("\1{}\3".format(\2))'),

        # Handle multiple variables in f-strings
        (r'f"([^"]*)\{([^}]+)\}([^"]*)\{([^}]+)\}([^"]*)"\)', r'"\1{}\3{}\5".format(\2, \4)'),
        (r'f"([^"]*)\{([^}]+)\}([^"]*)\{([^}]+)\}([^"]*)\{([^}]+)\}([^"]*)"\)', r'"\1{}\3{}\5{}\7".format(\2, \4, \6)'),

        # Simple f-strings
        (r'f"([^"]*)\{([^}]+)\}([^"]*)"\)', r'"\1{}\3".format(\2)'),
        (r"f'([^']*)\{([^}]+)\}([^']*)'\)", r"'\1{}\3'.format(\2)"),
    ]

    for pattern, replacement in replacements:
        content = re.sub(pattern, replacement, content)

    # Write back
    with open(filename, 'w') as f:
        f.write(content)

    print(f"Fixed {filename}")

if __name__ == "__main__":
    for filename in sys.argv[1:]:
        fix_file(filename)
EOF

python3 /tmp/fix_fstrings.py /root/BellNews2025/ubuntu_config_service.py /root/BellNews2025/bellapp/vcns_timer_web.py

echo "Syntax fixes applied!"

# Restart services
echo "Restarting services..."
sudo systemctl stop bellapp.service
sudo systemctl stop bellapp-config.service
sleep 2
sudo systemctl start bellapp-config.service
sleep 5
sudo systemctl start bellapp.service

echo "Services restarted!"

# Check status
sudo systemctl status bellapp-config.service --no-pager -l
sudo systemctl status bellapp.service --no-pager -l