# Reflections on Designing a Wallet Service

## Preface

此文主要是我们在设计钱包服务时的一些经验总结, 包括:

1. 细节方面的浮点数, 舍入, 金额的数据类型等
2. 宏观方面的代码质量, 单测, 风控等

此项目的难点在于两个方面:

1. 对数据一致性的要求, 钱多了钱少了都是大问题
2. 系统面向的是全球用户, 每个国家的币种, 汇率等都不一样, 如何在系统中统一表示

其实对于我们这样的小公司来说, 很多东西到不用考虑这么仔细, 但个人设计软件不喜欢有不清楚的地方,
所有的模糊的地方都必须搞明白, 这样才能提高软件的健壮性.
但是对于大公司来说, 细节是必须的, 毕竟一出问题就很严重,
对于一个需要运行很多年的银行系统来说, 这一点更为重要.

一些例子:

https://qr.ae/pr9I8r :

> As a Brazilian you might remember our inflation days
> when we need to change parts of accoing and other systems in days.

https://web.archive.org/web/20200920054816/https://status.aws.amazon.com/s3-20080720.html:

> More specifically, we found that there were a handful of messages on Sunday morning
> that had a single bit corrupted such that the message was still intelligible,
> but the system state information was incorrect.

## Microscopic view

### Floating Point

我们先来看一下例子:

```go
func ExampleFloatingPoint() {
	a, b := 1.1, 2.2
	fmt.Println(a + b)
	// Output: 3.3000000000000003
}
```

因为浮点数在计算机里面是近似表示的, 不是完全表示, 为什么会这么设计?
应该是为了效率吧, 毕竟上个世纪的电脑的性能跟现在比实在是天差地别.

我有一个猜想, 在进行小数字的计算的时候, 比如几亿以内的加减运算,
我们进行舍入的话应该能去掉这个误差,
一是我们能够确保小数点后面的精确位数是固定的, 毕竟货币都有最小单位.
二是两个数加减的误差应该是有个范围的, 根据浮点数的原理, 我们可以推导出误差的最大值,
如果误差在允许范围内, 那这样就是没有问题的.

### Rounding

在进行税额, 服务费, 货币转换的计算时, 肯定会出现小于最小货币单位的金额,
这时候就需要进行舍入了. 至于怎么舍入, 就属于业务的范畴了.
钱的总额是不会变的, 要么用户多得利一点, 要么公司多得利一点,
要么用一种分布比较均匀的公平算法, 如四舍六入五成双法.

扩展阅读:

1. [银行如何处理数据精度的，四舍五入是否有必要在银行系统中存在？ - 尚道的回答 - 知乎](https://www.zhihu.com/question/24580446/answer/640291950)
2. [金融系统如果产生多余两位小数位的金额怎么办？ - 腾讯云开发者社区-腾讯云](https://cloud.tencent.com/developer/article/1829858)

### Currency code

货币代码一般为三个字母, 再加三个字母的冗余, 因此最大长度设为 `6`.

参考 https://en.wikipedia.org/wiki/ISO_4217 :

> At the 17th session (February 1978), the related UN/ECE Group of Experts agreed that
> the **three-letter** alphabetic codes for International Standard ISO 4217

货币代码列表也可参考: https://www.iban.com/currency-codes

### Currency max amount

对于一些币值很小的货币, 如越南盾, 津巴布韦元, 需要考虑汇率换算之后的膨胀问题,
比如说假设人民币兑越南盾 1:3000, 换算成越南盾之后就膨胀了 3000 倍.

举个例子: 每个博主每月收入 10 万人民币, 有 1000 个达人, 每月总收入 1 亿,
一年 12 亿, 换算成某种不值钱的货币是 120000 亿 (`12000000000000`, 一共 14 位),
一不小心就会溢出. 所以这也是不能用浮点数的原因之一, 小数字可以进行舍去,
大数字就是真的表示不了那么精确的值.

### Currency decimal digits

实际上我们不必考虑金额的小数位数, 因为我们所用的整个技术栈都支持任意精度的小数,
以 PostgreSQL 的 numberic 类型为例[^1]:

> up to 131072 digits before the decimal point;
> up to 16383 digits after the decimal point

但是基于性能上的考量或者防御式编程, 我们最好还是限制一下位数.

货币的基本单位和最小单位在很多国家都是不一样的,
比如中国的基本单位是元, 最小单位是角 (小数点后两位), 美国的美元也是一样的,
但是日本就只有日元一个单位.
在存储金额时, 为了简化计算流程, 我们都会选择直接存储基本单位而不是最小单位,
所以我们需要确定金额小数点后最多能有多少位数字.

参考 https://en.wikipedia.org/wiki/ISO_4217 , 最多小数位数的是 4, 有如下国家:

| Code | Num | Digits | Currency                       | Locations |
| ---- | --- | ------ | ------------------------------ | --------- |
| CLF  | 990 | 4      | Unidad de Fomento (funds code) | Chile     |
| UYW  | 927 | 4      | Unidad previsional             | Uruguay   |

再加两个数字冗余, 最后我们选择了 6 位小数.

### Data types

因为浮点数的精度问题, 所以需要换种数据类型:

- ProtoBuf: `double`
  - pb 没有 `decimal` 类型, 所以只能用 `double`
  - pb 主要负责扔给前端显示, 不用计算 (加减乘除) 所以就不用担心精度问题
  - 其实用 `string` 类型也是可以的, 只是后端这边多额外判断一下 API 传入的字符串是否正确.
- Golang: `Decimal`
  - 使用的库是 [shopspring/decimal]
- Postgres: `numeric(19, 6)`
  - 支持小数点后六位, 一共 19 位数字
  - 最大值: 9999999999999.999999, 九万亿, 这应该足够了吧
- Exchange Rate: `double`
  - 汇率使用 64 位浮点数, 有 16 位有效数字 (float32 只有 7 位)
  - 这里感觉该使用 `decimal` 的, 统一类型, 代码也要简洁点
- 关于 [shopspring/decimal]:
  - 支持的数据库类型有 `float32`, `float64`, `int64`, `string`,
    See [code](https://github.com/shopspring/decimal/blob/f55dd564545cec84cf84f7a53fb3025cdbec1c4f/decimal.go#L1392)

扩展阅读:

1. [储存价格的字段，单位用元还是分好 - V2EX](https://www.v2ex.com/t/199222)
2. [大家平常都是以什么类型存储货币类型的数据？ - V2EX](https://www.v2ex.com/t/634439)
3. [准备开发和钱有关的功能，还有哪些地方要注意 - V2EX](https://www.v2ex.com/t/647058)
4. [涉及金钱存储或计算操作时，你们一般都使用什么数据类型 - V2EX](https://www.v2ex.com/t/683167)
5. [银行系统中对于「金额」使用怎样的数据类型？ - 沈万马的回答 - 知乎](https://www.zhihu.com/question/22536323/answer/348288089)

## Macroscopic view

### Code

想要提升代码质量,
一从人的角度上考虑:
要求程序员的思维足够严谨, 考虑到各种情况, 最好能举一反三,
由一种情况联想到另外一种情况. 在写 `if`, `switch` 语句的时候,
就尽量把所有分支情况都处理了, 虽然说有些分支目前来说不太可能会遇到,
但是说不定在未来某次迭代的时候这个分支就遇到了, 在未来你可能也忘记了还有这个分支,
这种情况非常常见, 一是没考虑到, 二是需求太急了没时间考虑.
我们提前处理好, 就提前阻止了系统进入一个无法预知情况的发生, 这也算是防御式编程吧.

二从工具角度上考虑:
使用拥有强大类型系统的语言, 编写完整的单元测试, lint 规则以及 CI/CD 流水线.
人多多少少会犯错, 使用工具能让我们避免低级错误, 在团队中也能使大家保持一致的代码风格等等.
以最近大火的 Rust 语言为例,
依靠强大的类型系统以及严苛的编程规范来强制程序员写出高质量的代码,
虽然这种语言的门槛比较高, 但是有舍有得.
我们团队使用的是 Golang, 虽然类型系统相较于其他一些语言 (Rust, Haskell...) 比较弱鸡,
但是作为一门简单好上手的静态编译语言, 结合一些 lint 工具 (如 [golangci-lint]),
开发体验还是挺不错的.

最后, 工具只是辅助, 优秀的程序员应该采用最简单直接的方式解决问题,
而不是像初级程序员一样绕来绕去.

### Unit test

单测: 这其实属于 Code 的一部分

重要的代码肯定要要求单测覆盖率的, 就不赘述了.

### Transaction

钱包系统就可以算是事务使用的典型场景了, 要保证数据的强一致性就肯定得用到事务, 具体来说:
在设计余额表的时候, 一般都会有一张余额流水表, 以记录余额变化的情况,
以及对应余额变化的业务表, 如提现就会对应一张提现表, 一次提现申请就会涉及到三张表的修改.

### Risk control

主要是异常监控, 复杂的风控以目前公司的技术实力还不行, 也没有必要.
参考墨菲定律, 大概率会发生各种异常情况, 比如异常的提现状态,
几张关联表的金额不一致等情况.
简单的实现就是: 定时任务 + SQL, 复杂的就参考下面:

- [GitHub - WalterInSH/risk-management-note: 🧯 风险控制笔记，适用于互联网企业](https://github.com/WalterInSH/risk-management-note)
- [一般的风控系统能识别到哪些客户端风险？ - V2EX](https://www.v2ex.com/t/866050)

## Extended Reading

1. 🌟 [大流量活动下钱包提现方案的设计与实现-51CTO.COM](https://www.51cto.com/article/707378.html)
   - 什么叫无懈可击的流程, 这就是
2. [基于 DDD 的虚拟钱包系统设计-云社区-华为云](https://bbs.huaweicloud.com/blogs/352998)
3. [提现业务的整套设计与流程，你都掌握了么？ | 人人都是产品经理](https://www.woshipm.com/pd/3905325.html)

[golangci-lint]: https://golangci-lint.run/
[shopspring/decimal]: https://github.com/shopspring/decimal

[^1]: https://www.postgresql.org/docs/current/datatype-numeric.html
