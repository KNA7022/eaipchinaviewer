import base64
import uuid
from urllib.parse import unquote
from io import BytesIO
from PIL import Image
import requests
from Crypto.PublicKey import RSA
from Crypto.Cipher import PKCS1_v1_5
import configparser
import time
from functools import wraps
from requests.exceptions import RequestException
import urllib3
import os

# 禁用不安全请求警告
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

def retry_on_failure(max_retries=3, delay=1):
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            retries = 0
            while retries < max_retries:
                try:
                    return func(*args, **kwargs)
                except RequestException as e:
                    retries += 1
                    if retries == max_retries:
                        print(f"请求失败，已重试{retries}次: {str(e)}")
                        raise
                    print(f"请求失败，正在进行第{retries}次重试...")
                    time.sleep(delay)
            return None
        return wrapper
    return decorator

class EaipLogin:
    def __init__(self):
        self.session = requests.Session()
        self.captcha_id = None
        self.base_dir = os.path.dirname(os.path.abspath(__file__))
        self.config = self._load_config()
        self.timeout = 30
        self.max_retries = 3
        
        # 更新所有默认请求头
        self.session.headers.update({
            'Accept': 'application/json, text/plain, */*',
            'Accept-Encoding': 'gzip, deflate, br, zstd',
            'Accept-Language': 'en-US',
            'Connection': 'keep-alive',
            'Host': 'www.eaipchina.cn',
            'Origin': 'https://www.eaipchina.cn',
            'Referer': 'https://www.eaipchina.cn/',
            'Sec-Fetch-Dest': 'empty',
            'Sec-Fetch-Mode': 'cors',
            'Sec-Fetch-Site': 'same-origin',
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36 Edg/134.0.0.0',
            'sec-ch-ua': '"Chromium";v="134", "Not:A-Brand";v="24", "Microsoft Edge";v="134"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"Windows"'
        })
        
        # 设置HTTPS验证选项
        self.session.verify = False
        
        # 如果配置了代理，设置代理
        if self.config.has_section('proxy'):
            proxy = self.config.get('proxy', 'http', fallback=None)
            if proxy:
                self.session.proxies = {'http': proxy, 'https': proxy}
        
    def _load_config(self):
        """加载配置文件"""
        config = configparser.ConfigParser()
        config_path = os.path.join(self.base_dir, 'config.ini')
        try:
            # 使用UTF-8编码读取配置文件
            with open(config_path, 'r', encoding='utf-8') as f:
                config.read_file(f)
        except Exception as e:
            print(f"加载配置文件失败: {str(e)}")
            raise
        return config
        
    def set_login_cookie(self, name, value):
        """设置登录Cookie和Token"""
        self.session.cookies.set(name, value, domain='www.eaipchina.cn')
        if name == "username":
            # 同时更新token头和cookie
            self.session.headers['token'] = value
            self.session.cookies.set(name, value, domain='www.eaipchina.cn')
        elif name == "userid":
            self.session.cookies.set("userId", value, domain='www.eaipchina.cn')
    
    def encrypt_password(self, password):
        """RSA加密密码"""
        public_key = '''-----BEGIN PUBLIC KEY-----
        MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCleaaZ4rYClmsDKlDXxrEZvRXs
        WqArQ4j+COOOyNLfJU3vSCrbSc1VcPEm3eOnPvSG3dhA0o9ttR+13g3kfi3gGvMc
        Yi9dTQ0ZIbHsXNze4vlI32yOmJjeig1ijlqivcVvJRk8c0HUlaWcmBqTDhMvN/lv
        yc7BQ34Ao/JH862rRQIDAQAB
        -----END PUBLIC KEY-----'''
        
        password = str(password).encode('utf-8')
        rsa_key = RSA.importKey(public_key)
        cipher = PKCS1_v1_5.new(rsa_key)
        encrypted = cipher.encrypt(password)
        encrypted_b64 = base64.b64encode(encrypted).decode('utf-8')
        return unquote(encrypted_b64)

    @retry_on_failure(max_retries=3, delay=2)  # 增加重试间隔
    def get_captcha(self):
        """获取验证码图片"""
        self.captcha_id = str(uuid.uuid4())
        captcha_url = f"https://www.eaipchina.cn/eaip/login/captcha?captchaId={self.captcha_id}"
        return self.session.get(
            captcha_url,
            timeout=self.timeout,
            allow_redirects=True
        )
    
    @retry_on_failure(max_retries=3, delay=2)
    def login_with_captcha(self, username, password, captcha_text):
        """使用验证码登录"""
        if not self.captcha_id:
            return False
            
        login_url = "https://www.eaipchina.cn/eaip/login/login"
        login_data = {
            "username": username,
            "password": self.encrypt_password(password),
            "captcha": captcha_text,
            "captchaId": self.captcha_id
        }
        
        try:
            response = self.session.post(
                login_url,
                json=login_data,
                timeout=self.timeout,
                allow_redirects=True,
                headers={'Content-Type': 'application/json'}
            )
            if response.status_code != 200:
                print(f"登录请求失败，状态码: {response.status_code}")
                return False
                
            data = response.json()
            if data.get("retCode") != 200:
                print(f"登录失败：{data.get('retMsg', '未知错误')}")
                return False
                
            token = data["data"]["token"]
            user_uuid = data["data"]["eaipUserUuid"]
            self.set_login_cookie("userid", user_uuid)
            self.set_login_cookie("username", token)
            return True
            
        except RequestException as e:
            print(f"登录请求异常: {str(e)}")
            return False

    @retry_on_failure(max_retries=3, delay=2)
    def get_publication_list(self):
        """获取航行资料列表"""
        url = "https://www.eaipchina.cn/eaip/publication/listByLoginPage"
        try:
            response = self.session.post(
                url,
                json={},  # 空JSON请求体
                timeout=self.timeout,
                headers={'Content-Type': 'application/json', 'Content-Length': '2'}
            )
            if response.status_code == 200:
                return response.json()
            return None
        except RequestException as e:
            print(f"获取资料列表失败: {str(e)}")
            return None

    def check_login_status(self, response_data):
        """检查登录状态"""
        if isinstance(response_data, dict):
            if response_data.get('retCode') == 0 and 'login has expired' in str(response_data.get('retMsg', '')):
                print("会话已过期，尝试重新登录...")
                return False
        return True

    @retry_on_failure(max_retries=3, delay=2)
    def get_package_list(self):
        """获取包列表"""
        url = "https://www.eaipchina.cn/eaip/package/listPage"
        try:
            headers = {
                'Content-Type': 'application/json',
                'Content-Length': '0'
            }
            # 第一次访问获取初始数据
            first_response = self.session.post(url, json={}, timeout=self.timeout, headers=headers)
            if first_response.status_code != 200:
                print(f"第一次请求失败，状态码: {first_response.status_code}")
                return None
            
            first_data = first_response.json()
            if not self.check_login_status(first_data):
                if not self.login():
                    return None
                # 重新尝试获取包列表
                first_response = self.session.post(url, json={}, timeout=self.timeout, headers=headers)
                
            print("等待1秒后重试...")
            time.sleep(1)
            
            # 第二次访问获取实际数据
            response = self.session.post(url, json={}, timeout=self.timeout, headers=headers)
            if response.status_code != 200:
                print(f"第二次请求失败，状态码: {response.status_code}")
                return None
                
            data = response.json()
            if not data:
                print("返回数据为空")
                return None
                
            if data.get('retCode') == 0:
                print(f"获取数据失败: {data.get('retMsg', '未知错误')}")
                if 'login has expired' in str(data.get('retMsg', '')):
                    if self.login():
                        # 重新尝试获取包列表
                        return self.get_package_list()
                return None
                
            return data
            
        except Exception as e:
            print(f"获取包列表失败: {str(e)}")
            return None

    def get_current_aip_structure(self):
        """获取当前版本的AIP目录结构"""
        for attempt in range(2):  # 最多尝试2次
            try:
                print("正在获取包列表...")
                packages = self.get_package_list()
                if not packages:
                    if attempt == 0:
                        print("尝试重新登录...")
                        if self.login():
                            continue
                    print("获取包列表失败")
                    return None
                
                if not isinstance(packages, dict):
                    print(f"包列表数据格式错误: {type(packages)}")
                    return None
                    
                print("解析包列表数据...")
                data = packages.get("data")
                if not data:
                    print("data字段为空")
                    return None
                    
                package_list = data.get("data")
                if not package_list:
                    print("没有找到包列表数据")
                    return None
                    
                print("查找当前生效版本...")
                # 获取当前生效的版本
                current_package = None
                for pkg in package_list:
                    if pkg.get("dataStatus") == "CURRENTLY_ISSUE":
                        current_package = pkg
                        break
                
                if not current_package:
                    print("未找到当前生效版本")
                    return None
                    
                print(f"找到当前版本: {current_package.get('dataName', 'unknown')}")
                print("正在获取AIP.JSON...")
                
                json_data = self.get_aip_json(current_package)
                if not json_data:
                    print("获取AIP.JSON失败")
                    return None
                    
                return json_data
                
            except Exception as e:
                print(f"获取目录结构时发生错误: {str(e)}")
                if attempt == 0:
                    print("尝试重新登录...")
                    if self.login():
                        continue
                return None
        return None

    @retry_on_failure(max_retries=3, delay=2)
    def get_pdf_url(self, package_info, pdf_path):
        """构建PDF文件的完整URL"""
        try:
            base_path = package_info["filePath"]  # 例如: packageFile/BASELINE/2025-02
            version = package_info.get("dataName", "").replace(" ", "")  # 例如: EAIP2025-02.V1.5
            if not base_path or not version or not pdf_path:
                return None
                
            url = f"https://www.eaipchina.cn/eaip/{base_path}/{version}/{pdf_path}"
            return url
            
        except Exception as e:
            print(f"构建PDF URL失败: {str(e)}")
            return None
            
    @staticmethod
    def parse_pdf_path(path):
        """从完整路径中提取PDF相对路径"""
        if not path:
            return None
        # 示例: /Data/EAIP2025-02.V1.5/Terminal/ZBAA/f1672224f816ae2bca16247c2c296461.pdf
        # 需要提取: Terminal/ZBAA/f1672224f816ae2bca16247c2c296461.pdf
        try:
            parts = path.split('/')
            if len(parts) >= 4:
                return '/'.join(parts[3:])
        except Exception:
            pass
        return None

    @retry_on_failure(max_retries=3, delay=2)
    def get_aip_json(self, package_info):
        """获取AIP.JSON文件内容"""
        try:
            # 使用固定格式的URL
            base_path = package_info["filePath"]
            url = f"https://www.eaipchina.cn/eaip/{base_path}/JsonPath/AIP.JSON"
            print(f"正在获取AIP数据: {url}")
            
            response = self.session.get(url, timeout=self.timeout)
            if response.status_code != 200:
                print(f"获取AIP.JSON失败, 状态码: {response.status_code}")
                return None
                
            data = response.json()
            if not data:
                print("获取到的AIP数据为空")
                return None
                
            return data
            
        except Exception as e:
            print(f"获取AIP.JSON失败: {str(e)}")
            return None

    @retry_on_failure(max_retries=3, delay=2)
    def validate_admin(self):
        """验证管理员权限"""
        url = "https://www.eaipchina.cn/eaip/user/validSuperAdmin"
        headers = {
            'Content-Length': '0'
        }
        try:
            response = self.session.post(url, data="", headers=headers, timeout=self.timeout)
            if response.status_code != 200:
                print(f"验证管理员权限失败，状态码: {response.status_code}")
                return None
            return response.json()
        except Exception as e:
            print(f"验证管理员权限请求失败: {str(e)}")
            return None

    def login(self):
        """执行登录流程"""
        try:
            print("正在获取验证码...")
            captcha_response = self.get_captcha()
            if not captcha_response or captcha_response.status_code != 200:
                print("获取验证码失败")
                return False
                
            # 保存并显示验证码
            with open("captcha.jpg", "wb") as f:
                f.write(captcha_response.content)
            img = Image.open(BytesIO(captcha_response.content))
            img.show()
            
            # 获取验证码输入
            captcha_text = input("请输入验证码: ")
            
            # 执行登录
            success = self.login_with_captcha(
                self.config.get('account', 'username'),
                self.config.get('account', 'password'),
                captcha_text
            )
            
            if success:
                print("登录成功！")
                # 获取航行资料列表
                pub_list = self.get_publication_list()
                if pub_list:
                    print("成功获取航行资料列表")
                return success
            else:
                print("登录失败！")
            return success
            
        except Exception as e:
            print(f"登录过程发生错误: {str(e)}")
            return False
