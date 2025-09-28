#!/usr/bin/env python3
"""
Fix Python 3.5 compatibility by converting f-strings to .format()
"""

import re
import os

def convert_fstrings_to_format(file_path):
    """Convert f-strings to .format() for Python 3.5 compatibility"""
    print(f"Processing {file_path}...")

    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    original_content = content

    # Pattern to match f-strings: f"text {variable} more text"
    # This is a simplified pattern - may need refinement for complex cases
    fstring_pattern = r'f"([^"]*\{[^}]*\}[^"]*)"'
    fstring_pattern2 = r"f'([^']*\{[^}]*\}[^']*)'"

    def replace_fstring(match):
        fstring_content = match.group(1)
        # Extract variables from {variable} patterns
        var_pattern = r'\{([^}]+)\}'
        variables = re.findall(var_pattern, fstring_content)

        # Replace {variable} with {0}, {1}, etc.
        format_string = fstring_content
        for i, var in enumerate(variables):
            format_string = format_string.replace('{' + var + '}', '{' + str(i) + '}')

        # Build the .format() call
        if variables:
            format_call = '"' + format_string + '".format(' + ', '.join(variables) + ')'
        else:
            format_call = '"' + format_string + '"'

        return format_call

    # Replace f-strings with double quotes
    content = re.sub(fstring_pattern, replace_fstring, content)
    # Replace f-strings with single quotes
    content = re.sub(fstring_pattern2, replace_fstring, content)

    if content != original_content:
        # Backup original file
        backup_path = file_path + '.backup'
        with open(backup_path, 'w', encoding='utf-8') as f:
            f.write(original_content)
        print(f"Backup created: {backup_path}")

        # Write fixed content
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"Fixed f-strings in {file_path}")
        return True
    else:
        print(f"No f-strings found in {file_path}")
        return False

if __name__ == "__main__":
    files_to_fix = [
        "/root/BellNews2025/ubuntu_config_service.py",
        "/root/BellNews2025/bellapp/vcns_timer_web.py"
    ]

    for file_path in files_to_fix:
        if os.path.exists(file_path):
            convert_fstrings_to_format(file_path)
        else:
            print(f"File not found: {file_path}")