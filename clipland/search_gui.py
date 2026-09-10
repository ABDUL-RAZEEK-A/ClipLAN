import os
import tkinter as tk
from tkinter import ttk, filedialog, messagebox

class CodebaseSearcher:
    def __init__(self, root):
        self.root = root
        self.root.title("ClipLAN Codebase Search")
        self.root.geometry("800x600")
        
        # Default to the current directory
        self.search_dir = os.path.abspath(os.path.dirname(__file__))
        
        self.setup_ui()
        
    def setup_ui(self):
        # Top Frame for Search Controls
        top_frame = ttk.Frame(self.root, padding=10)
        top_frame.pack(fill=tk.X)
        
        ttk.Label(top_frame, text="Directory:").pack(side=tk.LEFT, padx=5)
        self.dir_label = ttk.Label(top_frame, text=self.search_dir, width=40, anchor="w", background="white", relief="sunken")
        self.dir_label.pack(side=tk.LEFT, padx=5, fill=tk.X, expand=True)
        
        ttk.Button(top_frame, text="Change Folder", command=self.change_dir).pack(side=tk.LEFT, padx=5)
        
        # Second Frame for Keyword
        search_frame = ttk.Frame(self.root, padding=10)
        search_frame.pack(fill=tk.X)
        
        ttk.Label(search_frame, text="Keyword:").pack(side=tk.LEFT, padx=5)
        self.keyword_entry = ttk.Entry(search_frame, width=50)
        self.keyword_entry.pack(side=tk.LEFT, padx=5, fill=tk.X, expand=True)
        self.keyword_entry.bind('<Return>', lambda e: self.perform_search())
        
        ttk.Button(search_frame, text="Search Codebase", command=self.perform_search).pack(side=tk.LEFT, padx=5)
        
        # Results Frame
        results_frame = ttk.Frame(self.root, padding=10)
        results_frame.pack(fill=tk.BOTH, expand=True)
        
        # Scrollable Text Area for results
        self.results_text = tk.Text(results_frame, wrap=tk.NONE)
        
        vsb = ttk.Scrollbar(results_frame, orient="vertical", command=self.results_text.yview)
        hsb = ttk.Scrollbar(results_frame, orient="horizontal", command=self.results_text.xview)
        
        self.results_text.configure(yscrollcommand=vsb.set, xscrollcommand=hsb.set)
        
        self.results_text.grid(row=0, column=0, sticky="nsew")
        vsb.grid(row=0, column=1, sticky="ns")
        hsb.grid(row=1, column=0, sticky="ew")
        
        results_frame.grid_rowconfigure(0, weight=1)
        results_frame.grid_columnconfigure(0, weight=1)
        
        # Tag for highlighting
        self.results_text.tag_configure("match", background="yellow", foreground="black")
        self.results_text.tag_configure("file", foreground="blue", font=("TkDefaultFont", 10, "bold"))
        
    def change_dir(self):
        directory = filedialog.askdirectory(initialdir=self.search_dir)
        if directory:
            self.search_dir = directory
            self.dir_label.config(text=self.search_dir)
            
    def perform_search(self):
        keyword = self.keyword_entry.get().strip()
        if not keyword:
            messagebox.showwarning("Warning", "Please enter a keyword to search.")
            return
            
        self.results_text.delete(1.0, tk.END)
        self.results_text.insert(tk.END, f"Searching for '{keyword}' in {self.search_dir}...\n\n")
        
        exclude_dirs = {'.git', 'build', '.dart_tool', 'macos', 'ios', 'windows', 'linux', 'web'}
        exclude_exts = {'.png', '.jpg', '.jpeg', '.gif', '.ico', '.so', '.dll', '.dylib', '.zip', '.tar'}
        
        match_count = 0
        file_count = 0
        
        for root, dirs, files in os.walk(self.search_dir):
            # Mutate dirs in-place to skip excluded directories
            dirs[:] = [d for d in dirs if d not in exclude_dirs]
            
            for file in files:
                ext = os.path.splitext(file)[1].lower()
                if ext in exclude_exts:
                    continue
                    
                filepath = os.path.join(root, file)
                try:
                    with open(filepath, 'r', encoding='utf-8') as f:
                        lines = f.readlines()
                        
                    file_matches = []
                    for i, line in enumerate(lines):
                        if keyword.lower() in line.lower():
                            file_matches.append((i + 1, line.strip()))
                            match_count += 1
                            
                    if file_matches:
                        file_count += 1
                        rel_path = os.path.relpath(filepath, self.search_dir)
                        self.results_text.insert(tk.END, f"\n📄 {rel_path}\n", "file")
                        
                        for line_num, line_content in file_matches:
                            # Simple highlighting
                            self.results_text.insert(tk.END, f"  Line {line_num}: ")
                            
                            # Find keyword index for highlighting
                            lower_line = line_content.lower()
                            lower_kw = keyword.lower()
                            start_idx = 0
                            
                            while True:
                                idx = lower_line.find(lower_kw, start_idx)
                                if idx == -1:
                                    self.results_text.insert(tk.END, line_content[start_idx:] + "\n")
                                    break
                                
                                self.results_text.insert(tk.END, line_content[start_idx:idx])
                                self.results_text.insert(tk.END, line_content[idx:idx+len(keyword)], "match")
                                start_idx = idx + len(keyword)
                                
                except Exception:
                    # Ignore files that can't be read (binary files, permissions, etc)
                    pass
                    
        self.results_text.insert(tk.END, f"\n\n--- Search Complete: Found {match_count} matches in {file_count} files ---")

if __name__ == "__main__":
    root = tk.Tk()
    app = CodebaseSearcher(root)
    root.mainloop()
