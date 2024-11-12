import asyncio
from openai import AzureOpenAI
from typing import List, Dict
import json
from tqdm import tqdm
import re

class SQLMessageProcessor:
    def __init__(self, api_key: str, endpoint: str):
        self.client = AzureOpenAI(
            api_key=api_key,
            api_version="2024-02-15-preview",
            azure_endpoint=endpoint
        )
        self.translation_cache = {}
        
    async def identify_messages(self, text: str) -> List[Dict]:
        """使用GPT-4识别需要翻译的消息"""
        try:
            response = await asyncio.to_thread(
                self.client.chat.completions.create,
                model="gpt-40",
                messages=[
                    {"role": "system", "content": """
                    你是一个专门用于识别SQL代码中错误提示信息的AI助手。
                    请识别代码中包含 'ERROR_MESSAGE#' 或 'Info_MESSAGE#' 的消息。
                    
                    示例输入：
                    N'ERROR_MESSAGE#该箱码被用户xxx扫描，请提醒其操作!#The reception is completed!'
                    
                    请返回固定格式的JSON：
                    {
                        "messages": [
                            {
                                "full_text": "N'ERROR_MESSAGE#该箱码被用户xxx扫描，请提醒其操作!#The reception is completed!'",
                                "chinese": "该箱码被用户xxx扫描，请提醒其操作!",
                                "english": "The reception is completed!"
                            }
                        ]
                    }
                    
                    如果没有找到任何消息，返回：
                    {
                        "messages": []
                    }
                    """},
                    {"role": "user", "content": text}
                ],
                temperature=0,
                max_tokens=4000
            )
            result = response.choices[0].message.content.strip()
            
            # 调试信息
            print("\nGPT Response:", result)
            
            try:
                parsed_result = json.loads(result)
                if not isinstance(parsed_result, dict) or "messages" not in parsed_result:
                    print("Invalid JSON structure")
                    return []
                return parsed_result["messages"]
            except json.JSONDecodeError as je:
                print(f"JSON Parse Error: {je}")
                return []
                
        except Exception as e:
            print(f"Error identifying messages: {str(e)}")
            return []

    async def translate_text(self, text: str) -> str:
        """使用缓存和Azure GPT-4翻译文本"""
        if text in self.translation_cache:
            return self.translation_cache[text]
        
        try:
            response = await asyncio.to_thread(
                self.client.chat.completions.create,
                model="gpt-40",
                messages=[
                    {"role": "system", "content": """
                    你是一个专业的中英翻译器。
                    请将给定的中文错误提示准确翻译成英文。
                    要求：
                    1. 保持专业性和准确性
                    2. 使用简洁清晰的表达
                    3. 保持错误提示的语气
                    只返回翻译结果，不要添加任何解释。
                    """},
                    {"role": "user", "content": text}
                ],
                temperature=0
            )
            translation = response.choices[0].message.content.strip()
            self.translation_cache[text] = translation
            return translation
        except Exception as e:
            print(f"Translation error for '{text}': {str(e)}")
            return None

    def find_messages_in_chunk(self, chunk: str) -> List[Dict]:
        """使用正则表达式预处理查找可能的消息"""
        pattern = r"N'(?:ERROR_MESSAGE|Info_MESSAGE)#([^#]+)#([^']+)'"
        matches = re.finditer(pattern, chunk)
        messages = []
        for match in matches:
            messages.append({
                "full_text": match.group(0),
                "chinese": match.group(1),
                "english": match.group(2)
            })
        return messages

    async def process_file(self, input_file: str, output_file: str):
        """处理SQL文件并生成新文件"""
        try:
            # 尝试不同的编码方式读取文件
            encodings = ['utf-16', 'utf-16le', 'utf-8', 'gbk', 'gb2312', 'iso-8859-1']
            content = None
            used_encoding = None
            
            for encoding in encodings:
                try:
                    print(f"Trying to read file with {encoding} encoding...")
                    with open(input_file, 'r', encoding=encoding) as f:
                        content = f.read()
                        used_encoding = encoding
                        print(f"Successfully read file with {encoding} encoding")
                        break
                except UnicodeError:
                    continue
            
            if content is None:
                raise Exception("Could not read file with any known encoding")

            # 首先使用正则表达式找到所有可能的消息
            print("Pre-processing file to find potential messages...")
            all_messages = self.find_messages_in_chunk(content)
            print(f"Found {len(all_messages)} potential messages using regex")

            # 对找到的消息进行翻译
            new_content = content
            for msg in tqdm(all_messages, desc="Translating messages"):
                new_translation = await self.translate_text(msg['chinese'])
                if new_translation:
                    # 构建新的消息
                    new_message = msg['full_text'].replace(msg['english'], new_translation)
                    # 替换原文中的消息
                    new_content = new_content.replace(msg['full_text'], new_message)
                    print(f"\nTranslated: {msg['chinese']} -> {new_translation}")

            # 使用相同的编码写入新文件
            with open(output_file, 'w', encoding=used_encoding) as f:
                f.write(new_content)
            print(f"\nTranslation completed. Output written to {output_file}")

            # 保存翻译缓存
            with open('translation_cache.json', 'w', encoding='utf-8') as f:
                json.dump(self.translation_cache, f, ensure_ascii=False, indent=2)

        except Exception as e:
            print(f"Error processing file: {str(e)}")
            raise

async def main():
    # 配置Azure OpenAI
    api_key = "03531639fa37446dabac846c3e0e320c"
    endpoint = "https://dyopenaitest.openai.azure.com/"
    
    processor = SQLMessageProcessor(api_key, endpoint)
    
    # 加载已有的翻译缓存（如果存在）
    try:
        with open('translation_cache.json', 'r', encoding='utf-8') as f:
            processor.translation_cache = json.load(f)
    except FileNotFoundError:
        pass
    
    # 处理文件
    await processor.process_file(
        'SP_CESubmint.sql',
        'SP_CESubmint_translated.sql'
    )

if __name__ == "__main__":
    asyncio.run(main())