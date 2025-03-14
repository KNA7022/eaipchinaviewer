from eaip_login import EaipLogin
from aip_filter import AipFilter
import sys
import traceback
import time

def main():
    try:
        login = EaipLogin()
        if login.login():
            for attempt in range(3):  # 最多尝试3次
                print("\n开始获取AIP目录结构...")
                aip_structure = login.get_current_aip_structure()
                if aip_structure:
                    print("\n开始过滤目录内容...")
                    # 获取当前package信息
                    current_package = None
                    packages = login.get_package_list()
                    if packages and packages.get("data"):
                        package_list = packages["data"].get("data", [])
                        for pkg in package_list:
                            if pkg.get("dataStatus") == "CURRENTLY_ISSUE":
                                current_package = pkg
                                break
                    
                    # 传递package_info给filter_content
                    filtered_content = AipFilter.filter_content(aip_structure, current_package)
                    print("\n显示过滤后的目录结构:")
                    AipFilter.print_structure(filtered_content)
                    break
                else:
                    if attempt < 2:
                        print(f"第{attempt + 1}次获取失败，等待5秒后重试...")
                        time.sleep(5)
                    else:
                        print("\n获取目录结构最终失败")
        else:
            print("登录失败，请检查用户名密码或重试")
    except Exception as e:
        print(f"\n程序发生错误: {str(e)}")
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()
