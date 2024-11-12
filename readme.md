# SQL Message Translation System

一个用于翻译SQL错误提示消息的系统，支持中英文互译。

## 功能特点

- 自动识别SQL代码中的错误提示信息
- 支持中英文双向翻译
- 使用Azure OpenAI GPT模型进行翻译
- 翻译缓存功能，避免重复翻译
- 支持多种文件编码格式
- 批量处理能力

## 技术栈

- Python 3.x
- Azure OpenAI API
- SQL Server
- asyncio 异步处理

## 安装说明

1. 克隆项目到本地
2. 安装依赖包：
bash
pip install openai asyncio tqdm
3. 配置Azure OpenAI认证信息：
python
api_key = "your_api_key"
endpoint = "your_azure_endpoint"   

## 使用方法

1. 准备SQL文件
2. 运行翻译程序：
python
python translation.py

3. 查看生成的翻译结果文件

## 配置说明

### 翻译缓存配置
json:translation_cache.json
{
"chinese_message": "english_translation"
}

### 主要配置参数
- GPT模型：gpt-40
- 最大tokens：4000
- Temperature：0

## API文档

### SQLMessageProcessor类
主要方法：
- identify_messages(): 识别需要翻译的消息
- translate_text(): 翻译文本
- process_file(): 处理SQL文件
- find_messages_in_chunk(): 查找消息块

## 开发指南

1. 代码结构：
├── translation.py # 主程序
├── translation_cache.json # 翻译缓存
└── README.md # 说明文档

2. 关键代码参考：
- 消息识别逻辑：参考 `identify_messages()` 方法
- 翻译处理逻辑：参考 `translate_text()` 方法
- 文件处理逻辑：参考 `process_file()` 方法

## 注意事项

1. 确保Azure OpenAI API密钥配置正确
2. 处理大文件时注意内存使用
3. 建议定期备份translation_cache.json

## 许可证

MIT License

## 联系方式

- 作者：[王冰洁]
- 邮箱：[694623326@qq.com]