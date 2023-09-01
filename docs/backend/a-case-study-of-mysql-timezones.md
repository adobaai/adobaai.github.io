# A case study of MySQL timezones

1. 数据库表 `created_at` 显示的时间比本地时间快一个小时,

   数据库在韩国, 而韩国刚好比中国快一个小时, 猜测就是时区问题.

2. 检查 golang mysql driver:

   已设置 `parseTime=true&loc=Local`

3. 检查容器时间:

   `docker exec user-4c4x471 date`

   为 `Wed Aug 30 14:10:35 CST 2023`, 也是 +8 时区

   当然了, 因为 Dockerfile 有 `RUN cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime`

4. 手动在数据库新增一条数据, 发现时间也快一个小时,

   `created_at` 列设置了 `CURRENT_TIMESTAMP`, 大概率是数据库的问题了.

5. `SELECT LOCALTIME()` 返回 `2023-08-30 15:23:53`,

   也快一个小时, 确认是数据库的问题了.

6. `SHOW VARIABLES LIKE 'time_zone'`

   -> `Asia/Seoul`, 没毛病

7. 可是为什么接口返回的时间有时区, 而 `SELECT LOCALTIME()` 的结果是没有时区的.

8. 查看官方文档

   > MySQL converts TIMESTAMP values from the current time zone to UTC for storage,
   > and back from UTC to the current time zone for retrieval.
   > (This does not occur for other types such as DATETIME.)

   看来 DATETIME 没有保存时区, 应该是 mysql driver 自动加的时区, `loc=Local` 就是干这个事的.

9. 更进一步看 mysql driver 的源码:

   `const base = "0000-00-00 00:00:00.000000"`

   时区通过 `loc` 参数制定的.

   具体代码:

   https://github.com/go-sql-driver/mysql/blob/7cf548287682c36ebce3b7966f2693d58094bd5a/packets.go#L857

   https://github.com/go-sql-driver/mysql/blob/7cf548287682c36ebce3b7966f2693d58094bd5a/utils.go#L109

10. 解决方案一: 修改 driver 时区为韩国时区

    这个方法需要将数据库力量正常的时间 +1 个小时.

11. 解决方案二: 修改 mysql 时区为中国时区

    这个方法只需要将数据库自动生成时间的字段 -1 个小时

12. 比较来看, 方案二的要好一点, 因为修改工作量更少

13. MySQL 8.0.19 版本开始 datetime 支持时区了.

    > In MySQL 8.0.19 and later,
    > you can specify a time zone offset when inserting a TIMESTAMP or DATETIME value into a table.

    不过 `NOW()`, `CURRENT_TIMESTAMP()` 函数返回值依然没有添加时区,
    go mysql driver 发送给服务器的时间也没加时区.

    具体代码:

    https://github.com/go-sql-driver/mysql/blob/7cf548287682c36ebce3b7966f2693d58094bd5a/packets.go#L1207

    https://github.com/go-sql-driver/mysql/blob/7cf548287682c36ebce3b7966f2693d58094bd5a/utils.go#L268

14. 一句话: **人生苦短, 我用 PG**
