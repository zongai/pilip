<div align="center">
    <img width="200" height="200" src="assets/images/logo/logo.png" alt="PiliPlus logo">
    <h1>PiliPlus（本地增强版）</h1>
</div>

<div align="center">

中文 | [English](README.en.md)

![GitHub repo size](https://img.shields.io/github/repo-size/zongai/pilip)
![GitHub Repo stars](https://img.shields.io/github/stars/zongai/pilip)
![GitHub all releases](https://img.shields.io/github/downloads/zongai/pilip/total)

</div>

<div align="center">
    <p>基于 Flutter 的 Bilibili 第三方客户端 · 本仓库在上游基础上增加<strong>完全本地</strong>的关注 / 黑名单 / 播放列表等能力</p>
</div>

<br/>

## 本仓库说明

- **上游项目**：[bggRGjQaUbCoE/PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus)
- **本仓库**：[zongai/pilip](https://github.com/zongai/pilip)
- 在保留上游功能的同时，增加无需登录即可使用的本地功能；与官方关注 / 拉黑 / 稍后再看等接口**完全脱离**

<br/>

## 本地功能（无需登录）

在 **设置 → 隐私** 中开启「启用本地功能」后生效（部分入口需重启应用）。

| 功能 | 说明 |
|------|------|
| **本地黑名单** | 屏蔽指定 UP，相关内容在本地自动隐藏；不调用官方拉黑接口，不提示登录 |
| **本地关注** | 保存 UP 主页入口，点击进入主页；视频页 / UP 页显示「已关注」 |
| **本地播放列表** | 支持多个列表；视频菜单或 UP 投稿页可多选 / 全选加入；按标题排序；连续播放 |
| **本地观看记录** | 播放后自动记录，可查看 / 清空 |
| **本地稍后再看** | 视频菜单添加，无需登录 |
| **导入 / 导出** | 关注、黑名单、播放列表等可在设置中导入导出（JSON） |

### 入口位置

- 底栏：**首页**、**关注**、**合集 / 本地播放列表**、**我的**（启用本地后默认隐藏「动态」）
- **我的**：本地观看记录、稍后再看
- 视频页：菜单「加入本地播放列表」；连播时侧栏展示列表（图标入口在相关视频 / 评论行旁）

<br/>

## 适配平台

- [x] Windows（本仓库提供构建）
- [x] iOS（本仓库提供 IPA / SideStore 源）
- [x] Android / Pad / Linux（可自行基于源码编译）

<br/>

## 下载

从本仓库 [Releases](https://github.com/zongai/pilip/releases) 下载最新 **exe / zip / ipa**。

SideStore 源字段见仓库根目录 [`sidestore-apps.json`](sidestore-apps.json)。

<br/>

## 构建

使用 GitHub Actions 工作流（`win_x64.yml` / `ios.yml`）在 `main` 上 `workflow_dispatch` 构建；成功后自动发布带版本号的 Release。

```bash
git clone https://github.com/zongai/pilip.git
cd pilip
# 按上游文档配置 Flutter 环境后本地编译
```

<br/>

## 声明

此项目基于开源第三方客户端，仅用于学习与测试，请于下载后 24 小时内删除。  
所用 API 均来自官方公开接口，不提供任何破解内容。

致敬原作者：[guozhigq/pilipala](https://github.com/guozhigq/pilipala)  
致敬上游：[orz12/PiliPalaX](https://github.com/orz12/PiliPalaX)、[bggRGjQaUbCoE/PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus)

<br/>

## 致谢

- [bilibili-API-collect](https://github.com/SocialSisterYi/bilibili-API-collect)
- [media-kit](https://github.com/media-kit/media-kit)
- [dio](https://pub.dev/packages/dio)
- 以及上游 PiliPlus 全体贡献者

