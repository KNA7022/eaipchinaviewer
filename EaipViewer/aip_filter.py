import re
import os

class AipFilter:
    @staticmethod
    def filter_content(aip_json, package_info=None):
        """过滤AIP目录内容"""
        if not aip_json:
            print("没有获取到AIP数据")
            return []
            
        if not isinstance(aip_json, (list, dict)):
            print(f"无效的AIP数据格式: {type(aip_json)}")
            return []
            
        try:
            filtered = []
            pdf_paths = []  # 用于存储所有PDF路径
            
            if isinstance(aip_json, dict):
                aip_json = [aip_json]
            
            def should_keep_item(name_cn, full_path=[]):
                # 检查ENR章节
                if "ENR 6" in str(name_cn):
                    return True
                    
                # 检查是否为AD 2机场清单
                if "AD 2 机场清单" in str(name_cn):
                    return True
                    
                # 检查是否为机场ICAO代码开头的章节
                if re.match(r'Z[PBGHLSUWY][A-Z]{2}', str(name_cn)):
                    return True
                    
                # 如果是航图部分，总是保留父级目录下的所有内容
                parent_is_chart = any('机场清单' in p for p in full_path)
                if parent_is_chart and re.match(r'Z[PBGHLSUWY][A-Z]{2}-\d[A-Z]?\d?\d?', str(name_cn)):
                    return True
                
                return False
            
            def process_item(item, path=[]):
                if not isinstance(item, dict):
                    return None
                
                name_cn = item.get('name_cn', '')
                current_path = path + [name_cn]
                
                # 检查是否需要保留该项目
                keep_item = should_keep_item(name_cn, current_path)
                
                if keep_item:
                    processed_item = {
                        'name_cn': name_cn,
                        'Is_Modified': item.get('Is_Modified', 'N'),
                        'children': []
                    }
                    
                    # 如果需要保留且有PDF路径，则构建完整URL
                    pdf_path = item.get('pdfPath', '')
                    if pdf_path and package_info:
                        base_path = package_info["filePath"]
                        version = package_info.get("dataName", "").replace(" ", "")
                        full_url = f"https://www.eaipchina.cn/eaip/{base_path}/{pdf_path.split('/', 3)[-1] if '/' in pdf_path else pdf_path}"
                        pdf_paths.append(f"{name_cn}: {full_url}")
                    
                    # 处理子节点
                    children = item.get('children', [])
                    if children:
                        for child in children:
                            child_result = process_item(child, current_path)
                            if child_result:
                                processed_item['children'].append(child_result)
                    return processed_item
                
                # 如果当前节点不需要保留，但可能包含需要保留的子节点
                children = item.get('children', [])
                if children:
                    filtered_children = []
                    for child in children:
                        child_result = process_item(child, current_path)
                        if child_result:
                            filtered_children.append(child_result)
                    if filtered_children:
                        return {
                            'name_cn': name_cn,
                            'Is_Modified': item.get('Is_Modified', 'N'),
                            'children': filtered_children
                        }
                return None

            # 处理所有顶层节点
            for item in aip_json:
                result = process_item(item)
                if result:
                    filtered.append(result)
            
            # 保存PDF路径到文件
            output_dir = os.path.dirname(os.path.abspath(__file__))
            with open(os.path.join(output_dir, 'pdf_paths.txt'), 'w', encoding='utf-8') as f:
                f.write('\n'.join(pdf_paths))
            
            return filtered
            
        except Exception as e:
            print(f"过滤内容时发生错误: {str(e)}")
            return []

    @staticmethod
    def print_structure(filtered_content, level=0):
        """打印过滤后的目录结构"""
        if not filtered_content:
            print("未找到相关目录内容")
            return
            
        indent = "  " * level
        for item in filtered_content:
            # 获取中文名称和修改状态
            name_cn = item.get('name_cn', '未知标题')
            is_modified = item.get('Is_Modified', 'N')
            
            # 打印当前项
            prefix = "*" if is_modified == "Y" else "-"
            print(f"{indent}{prefix} {name_cn}")
            
            # 递归打印子目录
            children = item.get('children', [])
            if children:
                AipFilter.print_structure(children, level + 1)
