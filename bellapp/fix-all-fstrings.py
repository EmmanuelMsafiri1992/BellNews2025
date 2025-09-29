#!/usr/bin/env python3
"""
Comprehensive f-string to .format() converter for Python 3.5
"""

import re

def convert_file_fstrings(filename):
    """Convert all f-strings in a file to .format() syntax"""
    print("Converting f-strings in: {}".format(filename))

    with open(filename, 'r', encoding='utf-8') as f:
        content = f.read()

    # Backup
    with open(filename + '.before_fstring_fix', 'w', encoding='utf-8') as f:
        f.write(content)

    # Convert f-strings - handle single variable case
    def replace_single_var(match):
        before_text = match.group(1)
        variable = match.group(2)
        after_text = match.group(3)
        return '"{}{{}}{}"'.format(before_text, after_text) + '.format({})'.format(variable)

    # Pattern: f"text {variable} more text"
    content = re.sub(r'f"([^"]*?)\{([^}]+?)\}([^"]*?)"', replace_single_var, content)

    # Convert f-strings with two variables
    def replace_two_vars(match):
        p1, v1, p2, v2, p3 = match.groups()
        return '"{}{{}}{}{{}}{}"'.format(p1, p2, p3) + '.format({}, {})'.format(v1, v2)

    content = re.sub(r'f"([^"]*?)\{([^}]+?)\}([^"]*?)\{([^}]+?)\}([^"]*?)"', replace_two_vars, content)

    # Convert f-strings with three variables
    def replace_three_vars(match):
        p1, v1, p2, v2, p3, v3, p4 = match.groups()
        return '"{}{{}}{}{{}}{}{{}}{}"'.format(p1, p2, p3, p4) + '.format({}, {}, {})'.format(v1, v2, v3)

    content = re.sub(r'f"([^"]*?)\{([^}]+?)\}([^"]*?)\{([^}]+?)\}([^"]*?)\{([^}]+?)\}([^"]*?)"', replace_three_vars, content)

    # Handle f-strings with single quotes
    content = re.sub(r"f'([^']*?)\{([^}]+?)\}([^']*?)'", lambda m: "'{}{{}}{}'".format(m.group(1), m.group(3)) + '.format({})'.format(m.group(2)), content)

    # Remove any remaining f prefixes
    content = re.sub(r'\bf"([^"]*)"(?!\s*\.format)', r'"\1"', content)
    content = re.sub(r"\bf'([^']*)'(?!\s*\.format)", r"'\1'", content)

    # Write the fixed content
    with open(filename, 'w', encoding='utf-8') as f:
        f.write(content)

    print("Successfully converted f-strings in {}".format(filename))

if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1:
        for filename in sys.argv[1:]:
            convert_file_fstrings(filename)
    else:
        print("Usage: python3 fix-all-fstrings.py <filename>")