# -*- coding: utf-8 -*-

import re
import time
import json
import requests
from datetime import datetime, timedelta

import logging
from requests.exceptions import RequestException

logging.basicConfig(level=logging.INFO)

import utlis.json2html as json2html # 评论区html文件转换程序

# 进度条函数
def process_bar(start_num, end_num, start_str='Processing:', end_str='100%', total_length=40): 
    # eg: process_bar(i,len(srclist), start_str='Processing: ', end_str='100%', total_length=40) # 进度条
    try:
        percent = (start_num+1) / end_num
        bar = ''.join(["#%s"%''] * int(percent * total_length)) + ''
        bar = '\r' + start_str + bar.ljust(total_length) + ' {:0>4.1f}%|'.format(percent*100) + end_str
        print(bar, end='', flush=True)
    except:pass

def read_cookie_from_file_as_dict_list(cookies_path): # -> list(dict1, dict2, ...)
    cookies = []
    if cookies_path.endswith('.txt'):
        with open(cookies_path, 'r') as f:
            for line in f.read().split('\n'):
                if not line.startswith('#') and line.strip():
                    domain, _, path, secure, expiry, name, value = line.split('\t')
                    secure = True if secure.lower() == 'true' else False
                    expiry = int(expiry) if expiry else None
                    cookie = {'domain': domain, 'path': path, 'name': name, 'value': value, 'secure': secure, 'expiry': expiry}
                    cookies.append(cookie)             
    elif cookies_path.endswith('.json'):
        with open(cookies_path, 'r') as f:
            json_cookies = json.load(f)
            for json_cookie in json_cookies['cookies']:
                cookie = {
                    'domain': json_cookie['domain'], 
                    'name': json_cookie['name'], 
                    'value': json_cookie['value'], 
                    'secure': json_cookie['secure'],
                    'path': json_cookie['path']
                }
                cookies.append(cookie)
    return cookies


class BiliCommentsScraper:
    """
    用于从Bilibili视频获取并处理评论的爬虫。

    该类封装了获取视频信息、计算评论总页数、从每页中检索评论的方法。
    使用一个会话对象进行网络请求，通过复用底层TCP连接来提升性能。

    属性:
        session (requests.Session): 用于发起HTTP请求的会话对象。
        headers (dict): 请求时使用的HTTP头部。
        cookies (dict): 请求时使用的cookies。
        comments (list): 每页获取到的评论数据
        comments_per_page (int): 每页的评论数量，用于计算总页数。

    方法:
        run(): 执行爬取。
        save_to(comment_txt_path, comment_html_path): 保存评论区数据为txt, 然后生成html文件, html文件若不指定名称默认为原文件名+html
        fetch_json(url): 从给定URL获取并返回JSON数据。
        get_total_pages(url_api): 计算并返回视频评论的总页数。
        get_video_info(bv): 根据视频的BV号获取并返回视频标题。
        sanitize_title(title): 清理并返回标题字符串，使其适合作为文件名。
        get_url_info(url): 提取视频信息并构建评论API的URL。
        get_comment_data(url_api): 获取并处理视频所有页的评论。
        remove_duplicates(list_of_dicts): 去除jsonstyle dict list中的重复元素
    """
    
    def __init__(self, url, headers, cookies, show_process=False, max_comment_pages=None):
        self.session = requests.Session()
        self.url     = url
        self.headers = headers
        self.cookies = cookies
        self.comments = None
        self.comments_per_page = 20
        self.show_process = show_process
        self.max_comment_pages = max_comment_pages # 最大页数

    def run(self):
        url_api, _, _ = self.get_url_info(self.url)
        self.comments = self.get_comment_data(url_api)

    def save_to(self, comment_txt_path, comment_html_path=None):
        comments_unique = self.remove_duplicates(self.comments) 
        # 转换为json文本
        comments_unique_json_dict_list = self.convert_to_json_dict_list(comments_unique)
        # 将json文本写入文件，全体数据
        comments_unique_json_str = json.dumps(comments_unique_json_dict_list, ensure_ascii=False, indent=1)

        # 保存txt文件
        with open(comment_txt_path, 'w', encoding='utf-8-sig') as file:
            file.write(comments_unique_json_str)
        # print("\n    全体json数据已保存到txt文件", comment_txt_path)
        
        # 转换为html
        if not comment_html_path: # 如果没有指定输出文件路径，就使用输入文件路径并添加.html后缀
            comment_html_path = f"{comment_txt_path}.html"
        json2html.process_json_to_html(comment_txt_path, comment_html_path)

    def fetch_json(self, url, max_retries=3):
        for attempt in range(max_retries):
            try:
                time.sleep(0.5)
                response = self.session.get(url, headers=self.headers, cookies=self.cookies, timeout=60)
                response.raise_for_status()  # 如果状态不是200，将引发HTTPError异常
                return response.json()
            except RequestException as e:
                logging.error(f"请求失败（尝试 {attempt + 1}/{max_retries}）：{e}")
                if attempt == max_retries - 1:
                    logging.error("所有重试均失败")
                    return None
            except ValueError as e:
                logging.error(f"JSON解析失败：{e}")
                return None
        return None

    def get_total_pages(self, url_api):
        json_data = self.fetch_json(url_api.format(1))
        if json_data:
            try:
                total_comments = json_data["data"]["page"]["count"]
                total_pages = (total_comments - 1) // self.comments_per_page + 1
                if self.max_comment_pages:
                    total_pages = min(total_pages, self.max_comment_pages)
                    print(f"评论页数设定为{total_pages}页，大致所需时间{total_pages}s、{round(total_pages/60,1)}min")
                elif total_pages > 100:
                    total_pages = 100  # 假如总页数大于了100，就截断
                    print(f"评论页数超过100页，截断至100页，大致所需时间100s、{round(100/60,1)}min")
                else:
                    print(f"评论页数{total_pages}页，大致所需时间{total_pages}s、{round(total_pages/60,1)}min")
                return total_pages
            except KeyError as e:
                print(f"获取评论总数失败：{e}")
                print("JSON数据结构：", json.dumps(json_data, indent=2))
                return 0
        print("无法获取JSON数据")
        return 0

    def get_video_info(self, bv):
        url_info = f"https://api.bilibili.com/x/web-interface/view?bvid={bv}"
        json_data = self.fetch_json(url_info)
        if json_data:
            try:
                return json_data["data"]["title"]
            except KeyError:
                print("获取视频信息失败！")
        return None

    def sanitize_title(self, title):
        invalid_chars = r'[\/:*?"<>|]'
        return re.sub(invalid_chars, '_', title)

    def get_url_info(self, url):
        bv_pattern = re.compile(r'/(BV\w+)/')
        bv = bv_pattern.findall(url)[0]
        video_title = self.get_video_info(bv)
        if video_title:
            video_title = self.sanitize_title(video_title)
        url_api = "https://api.bilibili.com/x/v2/reply?pn={}&type=1&oid=" + bv +'&sort=1'
        return url_api, bv, video_title

    def convert_to_json_dict_list(self, data_all): # -> list(dict1, dict2, ...)
        def timestamp_to_beijing(timestamp):
            utc_datetime = datetime.utcfromtimestamp(timestamp)
            beijing_datetime = utc_datetime + timedelta(hours=8)
            return str(beijing_datetime)
        
        formatted_list = []  
        
        def extract_data(item):
            return {
                'username': item['member']['uname'],
                'comment': item['content']['message'],
                'like': item['like'],
                'posttime': timestamp_to_beijing(item['ctime'])  
            }
        
        for item in data_all:  
            comment_data = extract_data(item)  
            comment_data['replies'] = []
            
            if item['replies']:
                comment_data['replies'] = [extract_data(reply) for reply in item['replies']]
            
            formatted_list.append(comment_data)
        
        # 按照 like 降序进行排序
        sorted_list = sorted(formatted_list, key=lambda item: item['like'], reverse=True) 
        return sorted_list

    def remove_duplicates(self, list_of_dicts):  # 去重函数
        return [i for n, i in enumerate(list_of_dicts) if i not in list_of_dicts[n + 1:]]

    def get_comment_data(self, url_api) -> list:
        data = []
        total_pages = self.get_total_pages(url_api)
        if total_pages == 0:
            return data
            
        for i in range(1, total_pages + 1):
            time.sleep(0.1)
            url_page = url_api.format(i)
            json_data = self.fetch_json(url_page)
            if json_data["data"]:
                comments = json_data["data"]["replies"]
            if self.show_process:
                process_bar(i,total_pages + 1)
            if comments:
                for comment in comments:
                    data.append(comment)
        return data

if __name__ == '__main__':
    
    # 参数设定
    url = 'https://www.bilibili.com/video/BV1xk4y127Hy/' # 视频链接
    headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:123.0) Gecko/20100101 Firefox/123.0'}
    cookies_path = r".\cookies\www.bilibili.com_cookies[小号3].txt"
    comment_path = './comment.txt'

    # 读取cookies
    cookies = read_cookie_from_file_as_dict_list(cookies_path)
    cookies_dict = {cookie['name']: cookie['value'] for cookie in cookies}
    
    # 运行爬虫
    scraper = BiliCommentsScraper(url, headers, cookies_dict, show_process=True, max_comment_pages=None)
    scraper.run()
    scraper.save_to(comment_path) # 保存评论区数据并自动生成html文件

