# 来源与第三方代码

网页游戏发布文件下载自 https://breaking.de5.net/ ，日期为 2026-10-10。原始发布文件保存在 `web-original/`，其文件摘要见 `docs/provenance/download-manifest.json`。原游戏相关入口为 https://breakbreak.app/ 。本项目的可构建基线来自前者的已发布前端文件，并未取得后者的原作者开发仓库或服务器代码。

本项目的 Swift 应用、原生力度输入、本地成绩存储、启动设置及对游戏发布文件的改动由生成式人工智能生成。未取得原作者开发仓库，无法独立核实原网页全部代码的生成方式或授权条款。

启动弹窗按用户要求显示“所有代码为生成式人工智能生成”，并在同一弹窗标明第三方库和本移植代码的来源范围。该声明不改变原作品或第三方代码的版权归属。

发布脚本内包含 Three.js 图形库以及 Cannon 系列物理引擎代码。下方保留相关开源库的版权和许可说明；原游戏本身的许可未在下载的网页中公开。

本次移植与修改的可处分权利按 Unlicense 放弃，见 `LICENSE` 和 `LICENSING.md`。这不改变以下第三方许可，也不代替原游戏权利人处分其权利。

## Three.js — MIT

The MIT License

Copyright © 2010-2026 three.js authors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

## Cannon — MIT

/*
 * Copyright (c) 2015 cannon.js Authors
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation
 * files (the "Software"), to deal in the Software without
 * restriction, including without limitation the rights to use, copy,
 * modify, merge, publish, distribute, sublicense, and/or sell copies
 * of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
 * LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
 * OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
 * WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */
