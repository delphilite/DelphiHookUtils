# DelphiHookUtils

![Version](https://img.shields.io/badge/version-v1.0-yellow.svg)
![License](https://img.shields.io/github/license/delphilite/DelphiHookUtils)
![Lang](https://img.shields.io/github/languages/top/delphilite/DelphiHookUtils.svg)

Delphi API Hook 工具项目

## 由来

国庆帝都雾霾，一直闷家里发霉，也终于有时间搞搞自己的东东了！

年初基于 wr960204 武稀松大哥的 HookUtils 写了个 x64 的东东，效果很 8 错，不过呢，这个实现基于 BeaEngine 的静态库，额外胖了几百 K，对于我这只有“洁癖”的程序员，着实不爽！

之前关注过 BeaEngine 官网还有个 LDE64（Length Disassembler Engine）的东东，事实上对于武大哥那份 Hook 的实现，BeaEngine 只是为了查找足够的“代码间隙”，其实单个 LDE 应该是 ok 的！

遂，花了两天时间搞了这个东东：

[https://github.com/delphilite/DelphiHookUtils](https://github.com/delphilite/DelphiHookUtils)

## 实现

基于 LDE64 相对 BeaEngine 的优势非常明显，新 HookUtils 代码编译大约 10K 左右，相对武大哥“原版”，新版 HookUtils 主要修改：

 1. 参考 wr960204 武稀松 的原始实现： 
[https://code.google.com/p/delphi-hook-library](https://code.google.com/p/delphi-hook-library) 
 2. 修改 BeaEngine 引擎为 LDE64 长度反编译引擎，大幅降低大小
[https://github.com/BeaEngine/lde64](https://github.com/BeaEngine/lde64)
 3. 去除原始实现对多线程冻结的处理，通常建议 Hook/Unhook 放到单元初始化、析构中做，否则可能因改写内存没挂起其他线程造成错误 
 4. 由 HookUtils 中拆分 COM 相关函数至 HookIntfs 单元

## 其他

初步 Delphi 2007-12, Lazarus/Typhon/FPC/FMX x86/x64 for Win 一切正常，大家有问题及时反馈 ！？
