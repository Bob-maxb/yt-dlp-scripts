一、第一次上传
1. 在 GitHub 新建仓库

打开 https://github.com/new
Repository name 例如：yt-dlp-scripts
选 Public 或 Private
不要勾选 “Add a README”（本地已有文件时更省事）
Create repository

创建后页面会显示仓库地址，类似：
texthttps://github.com/你的用户名/yt-dlp-scripts.git

2. 在本地准备目录
建议单独一个只放要上传内容的文件夹，例如：
textD:\yt-dlp-git\
  download-movie.ps1
  query-JSON-v4.ps1
  config_movie
  Docs\yt-dlp_Guide_Complete.md
  .gitignore
.gitignore 内容示例：
textcookies.txt
*.exe
Logs/
*.log

3. 初始化并推送（PowerShell）
PowerShellcd D:\yt-dlp-git
初始化&提交
git init
git add .
git status
git commit -m "Initial commit: yt-dlp download scripts"

推送
git branch -M main
git remote add origin https://github.com/你的用户名/yt-dlp-scripts.git
git push -u origin main
浏览器登录 GitHub 账号即可（或按提示用 Personal Access Token）。

二、以后改完脚本怎么同步
在同一目录里：
PowerShellcd D:\yt-dlp\yt-dlp-git

git add .
git status
git commit -m "说明这次改了什么，例如: add ignore-no-formats-error"
git push

从 GitHub 拉到另一台电脑：
PowerShellgit clone https://github.com/你的用户名/yt-dlp-scripts.git
# 或已有仓库时：
git pull



设置 Git 用户信息（只需做一次）
把名字和邮箱换成你的（邮箱可用 GitHub 注册邮箱）：
PowerShellgit config --global user.name "Bob"
git config --global user.email "你的邮箱@example.com"