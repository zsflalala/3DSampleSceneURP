# 说明

本工程是将 [ShaderFallback](https://github.com/ShaderFallback) 的 [UnityVolumeCloud](https://github.com/ShaderFallback/UnityVolumeCloud) 仓库代码从普通的渲染管线迁移到URP渲染管线下的产物。

参考教程：
- [RayMarching实时体积云渲染入门](https://zhuanlan.zhihu.com/p/248406797)
- [在 Unity 中实现体积光渲染](https://zhuanlan.zhihu.com/p/124297905)
- [光线在参与介质中传输(体积散射的一些基本概念)](https://zhuanlan.zhihu.com/p/137653729)
- [体积云制作思路(实时渲染)unity、ue等游戏引擎通用](https://www.bilibili.com/video/BV1Bq4y1h7vX)
- [《荒野大镖客2》的大气云雾技术](https://zhuanlan.zhihu.com/p/91359727)
- [Ray Marching 101](https://zhuanlan.zhihu.com/p/34494449)
- [更通俗易懂之天空为啥那么蓝——瑞利散射](https://zhuanlan.zhihu.com/p/210745877)
- [unity3d shader之实时室外光线散射（大气散射）渲染](https://blog.csdn.net/wolf96/article/details/47144003)
- [unity3d shader之实时室外光线散射（大气散射）渲染](https://www.cnblogs.com/zhanlang96/p/4688219.html)
- [[图形学] 实时体积云（Horizon: Zero Dawn）](https://blog.csdn.net/ZJU_fish1996/article/details/89211634)
- [大气散射光照模型](https://blog.csdn.net/toughbro/article/details/7800395)
- [体渲染探秘（一）理论基础](https://zhuanlan.zhihu.com/p/348973932)
- [Ray Marching](https://michaelwalczyk.com/blog-ray-marching.html)
- [A Ray-Box Intersection Algorithm and Efficient Dynamic Voxel Rendering](https://jcgt.org/published/0007/03/04/)
- [光散射理论](https://zhuanlan.zhihu.com/p/401013637)
- [【GPU Pro 7】Real-Time Volumetric Cloudscapes](https://www.jianshu.com/p/ae1d13bb0d86)
- [米氏散射，瑞利散射，拉曼散射](https://zhuanlan.zhihu.com/p/463551881)

感谢 ShaderFallback 的无私分享，因而有机会能够学习到体积云效果的实现。

# Shader源码解析 & 原码解读 & 原理记录



# 提交记录

## 1.11 

参数面板和效果图：

![](doc\v3_参数面板.png)

![](doc\v3_效果图.jpg)
