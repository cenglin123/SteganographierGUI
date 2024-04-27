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
import subprocess
import string
from hachoir.parser import createParser
from hachoir.metadata import extractMetadata


def generate_random_filename(length=16):
    """生成指定长度的随机文件名, 不带扩展名"""
    chars = string.ascii_letters + string.digits
    return ''.join(random.choice(chars) for _ in range(length))

def format_duration(seconds):
    if seconds < 60:
        return f"{seconds}s"
    elif seconds < 3600:
        minutes = seconds // 60
        seconds = seconds % 60
        return f"{minutes}m:{seconds:02d}s"
    else:
        hours = seconds // 3600
        minutes = (seconds % 3600) // 60
        seconds = seconds % 60
        return f"{hours}h:{minutes:02d}m:{seconds:02d}s"

def get_video_duration(filepath):
    parser = createParser(filepath)
    if not parser:
        return "Unknown"
    try:
        metadata = extractMetadata(parser)
        if not metadata:
            return "Unknown"
        duration = metadata.get('duration')
        return format_duration(int(duration.seconds)) if duration else "Unknown"
    finally:
        parser.stream._input.close()

def get_video_files_info(folder_path):
    videos = []
    for filename in os.listdir(folder_path):
        if filename.endswith(".mp4") or filename.endswith(".mkv"):
            filepath = os.path.join(folder_path, filename)
            duration = get_video_duration(filepath)
            size = os.path.getsize(filepath) / (1024 * 1024)  # Convert bytes to MB
            videos.append(f"{filename} - {duration} - {size:.2f}MB")
    return videos

class SteganographierGUI:
    def __init__(self):
        self.mkvmerge_exe = os.path.join(application_path,'tools','mkvmerge.exe')
        self.mkvextract_exe = os.path.join(application_path,'tools','mkvextract.exe')
        self.mkvinfo_exe = os.path.join(application_path,'tools','mkvinfo.exe')
        self.title = "隐写者 Ver.1.0.4 GUI 作者: 层林尽染"
        self.video_file = None # 外壳MP4文件
        self.create_widgets() # GUI实现部分
        
    # 窗口控件初始化方法
    def create_widgets(self):
        self.root = TkinterDnD.Tk()
        self.root.title(self.title)
        self.root.iconbitmap(os.path.join(application_path,'modules','favicon.ico'))  # 设置窗口图标
        
        # 参数设定部分
        params_frame = tk.Frame(self.root)
        params_frame.pack(pady=5)
        self.password_label = tk.Label(params_frame, text="Password:")
        self.password_label.pack(side=tk.LEFT, padx=5)
        self.password_entry = tk.Entry(params_frame, width=25, show="*")
        self.password_entry.pack(side=tk.LEFT, padx=10)
        
        # 创建一个变量用于存储下拉菜单的选项
        self.type_option_var = tk.StringVar()
        self.type_option_var.set("mp4")  # 设置文件类型默认值
        self.type_option_label = tk.Label(params_frame, text="Output Type:")
        self.type_option_label.pack(side=tk.LEFT, padx=5, pady=5)
        self.type_option = tk.OptionMenu(params_frame, self.type_option_var, "mp4", "mkv") # 下拉菜单
        self.type_option.config(width=8)  # 设置宽度
        self.type_option.pack(side=tk.LEFT, padx=5, pady=5)
        
        self.hide_frame = tk.Frame(self.root, bd=2, relief=tk.GROOVE)
        self.hide_frame.pack(pady=10)
        self.hide_label = tk.Label(self.hide_frame, text="在此窗口中批量输入/拖入需要隐写的文件/文件夹:") 
        self.hide_label.pack()
        self.hide_text = tk.Text(self.hide_frame, width=65, height=5)
        self.hide_text.pack()
        self.hide_text.drop_target_register(DND_FILES)
        self.hide_text.dnd_bind("<<Drop>>", self.hide_files_dropped)
        
        self.reveal_frame = tk.Frame(self.root, bd=2, relief=tk.GROOVE)
        self.reveal_frame.pack(pady=10)
        self.reveal_label = tk.Label(self.reveal_frame, text="在此窗口中批量输入/拖入需要解除隐写的MP4/MKV文件:")
        self.reveal_label.pack()
        self.reveal_text = tk.Text(self.reveal_frame, width=65, height=5)
        self.reveal_text.pack()
        self.reveal_text.drop_target_register(DND_FILES)
        self.reveal_text.dnd_bind("<<Drop>>", self.reveal_files_dropped)
        
        self.video_folder_path = os.path.join(application_path, "cover_video")
        self.video_folder_label = tk.Label(self.root, text=f"外壳MP4文件存放路径: \n{self.video_folder_path}")
        self.video_folder_label.pack()

        # 获取外壳MP4视频文件列表和信息
        video_options = get_video_files_info(self.video_folder_path)
        self.video_option_var = tk.StringVar()
        if video_options:
            self.video_option_var.set(video_options[0])  # 默认选择第一个视频文件
        else:
            self.video_option_var.set("No videos found")
        
        self.video_option_menu = tk.OptionMenu(self.root, self.video_option_var, *video_options)
        self.video_option_menu.pack()
        
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

    def check_tools_existence(self):
        missing_tools = []
        for tool in [self.mkvmerge_exe, self.mkvinfo_exe, self.mkvextract_exe]:
            if not os.path.exists(tool):
                missing_tools.append(os.path.basename(tool))

        if missing_tools:
            messagebox.showwarning("Warning", "以下工具文件缺失，请在tools文件夹中添加后继续: " + ", ".join(missing_tools))
            return False
        return True

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
        
        if self.type_option_var.get() == 'mkv':
            if not self.check_tools_existence():
                # 结束后恢复按钮
                self.start_button.configure(state=tk.NORMAL)
                self.clear_button.configure(state=tk.NORMAL)
                return

        hide_file_paths = self.hide_text.get("1.0", tk.END).strip().split("\n")
        reveal_file_paths = self.reveal_text.get("1.0", tk.END).strip().split("\n")
        if not any(hide_file_paths) and not any(reveal_file_paths):
            messagebox.showwarning("Warning", "请输入或拖入文件.")
            # 结束后恢复按钮
            self.start_button.configure(state=tk.NORMAL)
            self.clear_button.configure(state=tk.NORMAL)
            return
        
        total_files = len(hide_file_paths) + len(reveal_file_paths)
        processed_files = 0
        
        # 1. 隐写流程
        for file_path in hide_file_paths:
            if file_path:
                self.hide_file(file_path, password)
                processed_files += 1
                self.update_progress(processed_files, total_files)
        
        # 2. 解除隐写流程
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
            # 结束后恢复按钮
            self.start_button.configure(state=tk.NORMAL)
            self.clear_button.configure(state=tk.NORMAL)
            return

        # # 随机选择一个外壳MP4文件用来隐写
        # video_file = random.choice(video_files)

        # 根据下拉菜单选择外壳MP4文件
        video_file = self.video_option_var.get() 
        video_file = video_file[:video_file.rfind('.mp4')]+'.mp4' # 按最后一个.mp4切分

        cover_video_path = os.path.join(self.video_folder_path, video_file)
        
        # 创建隐写的临时zip文件
        zip_file_path = os.path.join(os.path.splitext(file_path)[0] + "_hidden.zip")
        
        # 计算要压缩的文件总大小
        total_size = 0
        if os.path.isdir(file_path):
            for root, dirs, files in os.walk(file_path):
                for file in files:
                    file_full_path = os.path.join(root, file)
                    total_size += os.path.getsize(file_full_path)
        else:
            total_size = os.path.getsize(file_path)
        
        # mkv隐写单文件上限2GB
        if self.type_option_var.get() == 'mkv':
            if total_size > 2 * 1024 * 1024 * 1024:  # 2GB
                messagebox.showwarning(
                    "Warning",
                    f"mkv文件不能一次性隐写大小超过 2GB 的文件，此文件大小为 {total_size / (1024 * 1024 * 1024):.2f} GB. 请改换mp4模式或者分卷处理。"
                )
                # 结束后恢复按钮
                self.start_button.configure(state=tk.NORMAL)
                self.clear_button.configure(state=tk.NORMAL)
                return

        # 初始化已处理的大小为0
        processed_size = 0
        
        with pyzipper.AESZipFile(zip_file_path, 'w', compression=pyzipper.ZIP_DEFLATED, encryption=pyzipper.WZ_AES) as zip_file:
            zip_file.setpassword(password.encode())
            self.log(f"Compressing file: {file_path}")
            
            # 假如被隐写的文件是一个文件夹
            if os.path.isdir(file_path):
                # 定义总的顶层文件夹名为原文件夹的名字
                root_folder = os.path.basename(file_path)
                # 然后隐写其下所有文件
                for root, dirs, files in os.walk(file_path):
                    for file in files:
                        file_full_path = os.path.join(root, file)
                        # 在原有的相对路径前加上顶层文件夹名
                        arcname = os.path.join(root_folder, os.path.relpath(file_full_path, start=file_path))
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
        
        try:        
            # 1. 隐写MP4文件的逻辑
            if self.type_option_var.get() == 'mp4':
                output_file = os.path.splitext(file_path)[0] + "_hidden.mp4"
                self.log(f"Output file: {output_file}")
                total_size = os.path.getsize(cover_video_path) + os.path.getsize(zip_file_path)
                processed_size = 0
                with open(cover_video_path, "rb") as file1, open(zip_file_path, "rb") as file2, open(output_file, "wb") as output:
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
                #     cmd = f'copy /b "{cover_video_path}" + "{zip_file_path}" "{output_file}"'
                # else:  # For Unix-like systems
                #     cmd = f'cat "{cover_video_path}" "{zip_file_path}" > "{output_file}"'
                # subprocess.run(cmd, shell=True, check=True)
            
            # 2. 隐写mkv文件的逻辑
            elif self.type_option_var.get() == 'mkv':
                total_file_size = os.path.getsize(file_path)
                if total_file_size > 2 * 1024 * 1024 * 1024:  # 2GB
                    messagebox.showwarning(
                        "Warning",
                        f"mkv文件不能一次性隐写大小超过2GB的文件，此文件大小为{total_file_size / (1024 * 1024 * 1024):.2f} GB. 请改换mp4模式或者分卷处理。"
                    )
                    # 结束后恢复按钮
                    self.start_button.configure(state=tk.NORMAL)
                    self.clear_button.configure(state=tk.NORMAL)
                    return
                
                output_file = os.path.splitext(file_path)[0] + "_hidden.mkv"
                self.log(f"Output file: {output_file}")
                cmd = [
                    self.mkvmerge_exe, '-o',
                    output_file, cover_video_path,
                    '--attach-file', zip_file_path,
                ]
                self.log(f"Hiding file: {file_path}")
                result = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8')
                if result.returncode != 0:
                    raise subprocess.CalledProcessError(result.returncode, cmd, output=result.stdout, stderr=result.stderr)

        except subprocess.CalledProcessError as cpe:
            self.log(f"隐写时发生错误: {str(cpe)}")
            self.log(f'CalledProcessError output：{cpe.output}') if cpe.output else None
            self.log(f'CalledProcessError stderr：{cpe.stderr}') if cpe.stderr else None

        except Exception as e:
            self.log(f"隐写时发生未预料的错误: {str(e)}")

        # 删除临时zip文件
        os.remove(zip_file_path)

        self.log(f"Output file created: {os.path.exists(output_file)}")
    
    
    # 解除隐写的方法      
    def reveal_file(self, file_path, password):
        
        # 解除MP4隐写的逻辑
        if self.type_option_var.get() == 'mp4':
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
                    # 删除ZIP文件
                    os.remove(zip_path)
                    self.log(f"文件 {file_path} 不存在隐写内容。")
                
            except pyzipper.BadZipFile:
                self.log(f"文件 {file_path} 不存在隐写内容或密码错误。")
            except Exception as e:
                self.log(f"解除隐写时发生错误: {str(e)}")
        
        # 解除mkv文件隐写的逻辑
        elif self.type_option_var.get() == 'mkv':
            # 获取mkv附件id函数
            def get_attachment_name(file_path):
                cmd = [self.mkvinfo_exe, file_path]
                try:
                    result = subprocess.run(cmd, capture_output=True, text=True, check=True, encoding='utf-8')
                    lines = result.stdout.splitlines()
                    for idx, line in enumerate(lines):
                        if "MIME" in line:
                            parts = lines[idx-1].split(':')
                            attachments_name = parts[1].strip().split()[-1] # 附件的实际名称
                except Exception as e:
                    self.log(f"获取附件时出错: {e}")
                
                return attachments_name
            
            # 提取mkv附件
            def extract_attachment(file_path, output_path):
                cmd = [
                    self.mkvextract_exe, 'attachments',
                    file_path,
                    f'1:{output_path}'
                ]
                try:
                    subprocess.run(cmd, check=True)
                except subprocess.CalledProcessError as e:
                    raise Exception(f"提取附件时出错: {e}")   
                    
            # 获取附件文件名
            attachments_name = get_attachment_name(file_path)
            if attachments_name:
                output_path = os.path.join(os.path.dirname(file_path), attachments_name)
                self.log(f"Mkvextracting attachment file: {output_path}")
                # 提取附件
                try:
                    extract_attachment(file_path, output_path)

                    # 使用密码解压ZIP文件
                    if attachments_name.endswith('.zip'):
                        try:
                            zip_path = output_path
                            self.log(f"Extracting ZIP file: {zip_path}")
                            with pyzipper.AESZipFile(zip_path, 'r', compression=pyzipper.ZIP_DEFLATED, encryption=pyzipper.WZ_AES) as zip_file:
                                zip_file.extractall(os.path.dirname(file_path), pwd=password.encode())
                            
                            # 解压后删除ZIP文件
                            os.remove(zip_path)
                    
                        except RuntimeError as e:
                            # 这里处理密码错误的情况
                            self.log(f"解压失败，错误信息: {e}")

                    # 解压后删除隐写MP4文件
                    os.remove(file_path)
                    
                    self.log(f"提取附件 {attachments_name} 成功")
                except subprocess.CalledProcessError as e:
                    self.log(f"提取附件 {attachments_name} 时出错: {e}")

            else:
                self.log("该 MKV 文件中没有可提取的附件。")


if __name__ == "__main__":
    
    # 关于程序执行路径的问题
    if getattr(sys, 'frozen', False):
        # 打包成exe的情况
        application_path = os.path.dirname(sys.executable)
    else:
        # 在开发环境中运行
        application_path = os.path.dirname(__file__)
        
    SteganographierGUI()
