import os
import sys

def replace_in_file(filepath):
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
    except UnicodeDecodeError:
        return # Skip binary files

    new_content = content.replace("ClipLAN", "ClipLAN")
    
    if new_content != content:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print(f"Updated: {filepath}")

def main():
    root_dir = "/Users/abdul_razeek_a/Myself/projects/Projects/MAD "
    exclude_dirs = {'.git', 'build', '.dart_tool', '.idea', 'ios/Pods', 'macos/Pods'}
    exclude_exts = {'.png', '.jpg', '.jpeg', '.gif', '.mp4', '.aab', '.apk', '.dmg', '.exe', '.pdf', '.docx', '.zip'}

    for dirpath, dirnames, filenames in os.walk(root_dir):
        # Modify dirnames in-place to ignore exclude_dirs
        dirnames[:] = [d for d in dirnames if d not in exclude_dirs and not d.endswith('.framework')]

        for filename in filenames:
            ext = os.path.splitext(filename)[1].lower()
            if ext in exclude_exts:
                continue
            
            filepath = os.path.join(dirpath, filename)
            replace_in_file(filepath)

if __name__ == "__main__":
    main()
