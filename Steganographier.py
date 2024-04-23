# -*- coding: utf-8 -*-
"""
Created on Mon Apr 22 14:56:41 2024

    隐写者源代码

pip install tkinterdnd2
pip install pyzipper

@author: Cr
"""

import os
import sys
# import shutil
import random
import tkinter as tk
from tkinter import  messagebox, ttk
from tkinterdnd2 import DND_FILES, TkinterDnD
import pyzipper
import threading
# import subprocess

class SteganographierGUI:
    def __init__(self):
	    # GUI实现部分
        self.root = TkinterDnD.Tk()
        self.root.title("隐写者 Ver.1.0.0 GUI 作者: 层林尽染")
        self.root.iconbitmap(os.path.join(application_path,'modules','favicon.ico'))  # 设置窗口图标
                
        self.password_label = tk.Label(self.root, text="Password:")
        self.password_label.pack()
        self.password_entry = tk.Entry(self.root, show="*")
        self.password_entry.pack()
        
        self.hide_frame = tk.Frame(self.root, bd=2, relief=tk.GROOVE)
        self.hide_frame.pack(pady=10)
        self.hide_label = tk.Label(self.hide_frame, text="在此窗口中输入/拖入需要隐写的文件/文件夹:") 
        self.hide_label.pack()
        self.hide_text = tk.Text(self.hide_frame, width=65, height=5)
        self.hide_text.pack()
        self.hide_text.drop_target_register(DND_FILES)
        self.hide_text.dnd_bind("<<Drop>>", self.hide_files_dropped)
        
        self.reveal_frame = tk.Frame(self.root, bd=2, relief=tk.GROOVE)
        self.reveal_frame.pack(pady=10)
        self.reveal_label = tk.Label(self.reveal_frame, text="在此窗口中输入/拖入需要解除隐写的MP4文件:")
        self.reveal_label.pack()
        self.reveal_text = tk.Text(self.reveal_frame, width=65, height=5)
        self.reveal_text.pack()
        self.reveal_text.drop_target_register(DND_FILES)
        self.reveal_text.dnd_bind("<<Drop>>", self.reveal_files_dropped)
        
        self.video_folder_path = os.path.join(application_path, "cover_video")
        self.video_folder_label = tk.Label(self.root, text=f"外壳MP4文件存放路径: \n{self.video_folder_path}")
        self.video_folder_label.pack()
        
        # log文本框
        self.log_text = tk.Text(self.root, width=65, height=10, state=tk.NORMAL)
        self.log_text.insert(tk.END, "Console output goes here...\n")
        self.log_text.configure(state=tk.DISABLED, fg="grey")
        self.log_text.pack()
        
        # 按钮部分
        button_frame = tk.Frame(self.root)
        button_frame.pack(pady=10)
        
        self.start_button = tk.Button(button_frame, text="开始执行", command=self.start_thread, width=10, height=2)
        self.start_button.pack(side=tk.LEFT, padx=5)
        
        self.clear_button = tk.Button(button_frame, text="清除窗口", command=self.clear, width=10, height=2)
        self.clear_button.pack(side=tk.LEFT, padx=5)
        
        # 进度条
        self.progress = ttk.Progressbar(self.root, length=500, mode='determinate')
        self.progress.pack(pady=10)
        
        self.root.mainloop()
        
    def log(self, message):
        self.log_text.configure(state=tk.NORMAL, fg="grey")
        self.log_text.insert(tk.END, message + "\n")
        self.log_text.configure(state=tk.DISABLED, fg="grey")
        self.log_text.see(tk.END)
        self.log_text.update_idletasks()
    
    def hide_files_dropped(self, event):
        file_paths = self.root.tk.splitlist(event.data)
        self.hide_text.insert(tk.END, "\n".join(file_paths) + "\n")
    
    def reveal_files_dropped(self, event):
        file_paths = self.root.tk.splitlist(event.data)
        self.reveal_text.insert(tk.END, "\n".join(file_paths) + "\n")
    
    def start_thread(self):
        threading.Thread(target=self.start).start()
    
    def start(self):
        # 开始后禁用start和clear按钮
        self.start_button.configure(state=tk.DISABLED)
        self.clear_button.configure(state=tk.DISABLED)
        
        self.progress['value'] = 0
        
        password = self.password_entry.get()
        if not password:
            messagebox.showwarning("Warning", "请指定密码.")
            # 结束后恢复按钮
            self.start_button.configure(state=tk.NORMAL)
            self.clear_button.configure(state=tk.NORMAL)
            return
        
        hide_file_paths = self.hide_text.get("1.0", tk.END).strip().split("\n")
        reveal_file_paths = self.reveal_text.get("1.0", tk.END).strip().split("\n")
        
        total_files = len(hide_file_paths) + len(reveal_file_paths)
        processed_files = 0
        
        for file_path in hide_file_paths:
            if file_path:
                self.hide_file(file_path, password)
                processed_files += 1
                self.update_progress(processed_files, total_files)
        
        for file_path in reveal_file_paths:
            if file_path:
                self.reveal_file(file_path, password)
                processed_files += 1
                self.update_progress(processed_files, total_files)
        
        messagebox.showinfo("Success", "所有操作已完成！")
        # 结束后恢复按钮
        self.start_button.configure(state=tk.NORMAL)
        self.clear_button.configure(state=tk.NORMAL)
        
    def update_progress(self, processed_size, total_size):
        progress = (processed_size+1) / total_size
        self.progress['value'] = progress * 100
        self.root.update_idletasks()
    
    def clear(self):
        self.hide_text.delete("1.0", tk.END)
        self.reveal_text.delete("1.0", tk.END)
        
        self.log_text.configure(state=tk.NORMAL, fg="grey")
        self.log_text.delete("1.0", tk.END)
        self.log_text.insert(tk.END, "Console output goes here...\n")
        self.log_text.configure(state=tk.DISABLED, fg="grey")

    def read_in_chunks(self, file_object, chunk_size=1024*1024):
        while True:
            data = file_object.read(chunk_size)
            if not data:
                break
            yield data

    # 隐写方法实现部分
    def hide_file(self, file_path, password):
        # 检查cover_video中是否存在用来作为外壳的MP4文件（比如海绵宝宝之类，数量任意，每次随机选择）
        video_files = [f for f in os.listdir(self.video_folder_path) if f.endswith(".mp4")]
        if not video_files:
            messagebox.showwarning("Warning", "cover_video 文件夹下没有文件，请添加文件后继续.")
            return
        
        # 随机选择一个外壳MP4文件用来隐写
        video_file = random.choice(video_files)
        video_path = os.path.join(self.video_folder_path, video_file)
        
        # 隐写临时文件
        zip_file_path = os.path.splitext(file_path)[0] + ".zip"
        
        # 计算要压缩的文件总大小
        total_size = 0
        if os.path.isdir(file_path):
            for root, dirs, files in os.walk(file_path):
                for file in files:
                    file_full_path = os.path.join(root, file)
                    total_size += os.path.getsize(file_full_path)
        else:
            total_size = os.path.getsize(file_path)
        
        # 初始化已处理的大小为0
        processed_size = 0
        
        with pyzipper.AESZipFile(zip_file_path, 'w', compression=pyzipper.ZIP_DEFLATED, encryption=pyzipper.WZ_AES) as zip_file:
            zip_file.setpassword(password.encode())
            self.log(f"Compressing file: {zip_file_path}")
            
            # 假如被隐写的文件是一个文件夹
            if os.path.isdir(file_path):
                # 则隐写其下所有文件
                for root, dirs, files in os.walk(file_path):
                    for file in files:
                        file_full_path = os.path.join(root, file)
                        arcname = os.path.relpath(file_full_path, start=file_path)
                        zip_file.write(file_full_path, arcname)
                        
                        # 更新已处理的大小并更新进度条
                        processed_size += os.path.getsize(file_full_path)
                        self.update_progress(processed_size, total_size)
            else:
                # 更新已处理的大小并更新进度条
                processed_size = total_size
                self.update_progress(processed_size, total_size)
                
                # 否则只隐写该文件
                zip_file.write(file_path, os.path.basename(file_path))
                
        
        # 隐写文件的逻辑
        output_file = os.path.splitext(file_path)[0] + "_hidden.mp4"
        self.log(f"Output file: {output_file}")
        total_size = os.path.getsize(video_path) + os.path.getsize(zip_file_path)
        processed_size = 0
        with open(video_path, "rb") as file1, open(zip_file_path, "rb") as file2, open(output_file, "wb") as output:
            self.log(f"Hiding file: {file_path}")
            for chunk in self.read_in_chunks(file1):
                output.write(chunk)
                processed_size += len(chunk)
                self.update_progress(processed_size, total_size)
            
            for chunk in self.read_in_chunks(file2):
                output.write(chunk)
                processed_size += len(chunk)
                self.update_progress(processed_size, total_size)
                
        # # 也可以用shell指令完成隐写，但打包后容易出莫名其妙的bug，故弃用
        # if os.name == 'nt':  # Windows
        #     cmd = f'copy /b "{video_path}" + "{zip_file_path}" "{output_file}"'
        # else:  # For Unix-like systems
        #     cmd = f'cat "{video_path}" "{zip_file_path}" > "{output_file}"'
        # subprocess.run(cmd, shell=True, check=True)
        
        # 删除临时zip文件
        os.remove(zip_file_path)

        self.log(f"Output file created: {os.path.exists(output_file)}")
        
    # 解除隐写的方法      
    def reveal_file(self, file_path, password):
        try:
            # 读取文件数据
            self.log(f"Revealing file: {file_path}")
            with open(file_path, "rb") as file:
                file_data = file.read()
            
            # 尝试提取ZIP数据
            try:
                zip_data = file_data[len(file_data) - os.path.getsize(file_path):]
                
                # 将ZIP文件写入硬盘
                zip_path = os.path.splitext(file_path)[0] + "_extracted.zip"
                with open(zip_path, "wb") as file:
                    file.write(zip_data)
                
                # 使用密码解压ZIP文件
                self.log(f"Extracted ZIP file: {zip_path}")
                with pyzipper.AESZipFile(zip_path, 'r', compression=pyzipper.ZIP_DEFLATED, encryption=pyzipper.WZ_AES) as zip_file:
                    zip_file.extractall(os.path.dirname(file_path), pwd=password.encode())
                
                # 删除ZIP文件
                os.remove(zip_path)
                
                # 删除隐写MP4文件
                os.remove(file_path)
                
                self.log(f"ZIP file extracted: {not os.path.exists(zip_path)}")
                
            except (pyzipper.BadZipFile, ValueError):
                self.log(f"文件 {file_path} 不存在隐写内容。")
            
        except pyzipper.BadZipFile:
            self.log(f"文件 {file_path} 不存在隐写内容或密码错误。")
        except Exception as e:
            self.log(f"解除隐写时发生错误: {str(e)}")
        
if __name__ == "__main__":
    
    # 关于程序执行路径的问题
    if getattr(sys, 'frozen', False):
        # 打包成exe的情况
        application_path = os.path.dirname(sys.executable)
    else:
        # 在开发环境中运行
        application_path = os.path.dirname(__file__)
        
    SteganographierGUI()