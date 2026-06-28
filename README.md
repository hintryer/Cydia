# 仓库说明

这个仓库用于自动构建并发布 Cydia/Sileo/Apt 软件源。

## 使用方法

1. 将 .deb 包上传到 debians/ 目录。
2. GitHub Actions 会自动运行 update.sh，生成 Packages、Release 等仓库索引文件。
3. 如果文件变更，Action 会自动提交并推送更新。

## 目录说明

- debians/：存放所有 .deb 软件包。
- update.sh：入口脚本，调用 updaterepo.sh 进行仓库构建。
- .github/workflows/main.yml：自动化构建与发布配置。
- assets/repo/repo.conf：APT 仓库元信息配置。

## 额外说明

- 如果使用固定签名密钥，请在 GitHub Secrets 中添加 REPO_GPG_PRIVATE_KEY。
- 你可以修改 index.html 和 style.css，优化仓库网页展示。
