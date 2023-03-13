#!/usr/bin/perl

# 引用当前目录下面的模块*****
BEGIN{push @INC, ".";}

use strict;
use warnings;
use Memory;
use Utils;
use GenerateData;

# 分析redis memory csv 的perl脚本
# 1、处理千分位问题 // done
# 2、合并千分位的key，生成一个新的文件（txt、csv）,保存到数据库。 //not must todo
# 3、统计出所有的key的大概内存分布情况 // done
# 4、识别脏key // not must todo (人工识别)
# 5、筛选出来过大的key //done top10 memory 、top10 count
# 6、对比多个文件并且生成对比的结果文件。//must todo
#    1、数量
#    2、内存
# 7、修改成一个cli程序（支持多种操作）//not must todo
# 	  7.1 获取全部的缓存大小
# 	  7.2 分析统计每个类型的业务key分别占有多少内存大小
# 8、输出结果集到数据库，使用前端的一些js组件进行对比展示 //must todo
# 9、重构代码（封装抽取） // not must todo

# 存放多个redis csv内存文件分析结果
my %redis_memory_data  = ();

foreach my $f (@ARGV) {
    # 命令行读取参数（csv文件）
    my $file_name = get_file_name($f);
    my $memory = key_count($f,$file_name);
    $redis_memory_data{$file_name}= $memory;
}
generate_line_data(\%redis_memory_data);

# 计算整体的key的数量、大小（排除掉脏key）
# 按照逗号进行切割,再按照:切割（9位的需要合并之后再进行切割，8位直接的可以使用）
# 根据不同的名字进行存储
sub key_count{
    my $file = $_[0];
    my $file_name = $_[0];
    my $sum = 0;
    my $comma_separator = ",";
    my $semicolon_separator = ":";
	my $exception_count = 9;
    my $count_limit  = 0;
    my $memory_limit = 0;
    open( my $data, '<', $file ) or die "Could not open '$file' $!\n";
	readline $data; # 跳过第一行
    my %redis_key_count_data  = ();
    my %redis_key_memory_data = ();
    my %map_keys = (); # 正则替换完之后的key映射
    while ( my $line = <$data> ) {
        chomp $line;
        my @fields  = split $comma_separator , $line;
        my $size    = @fields;
        my $new_key = "";
        my $memmory_size = 0;
        if ( $size == $exception_count ) {
            $new_key = $fields[2];
            $new_key .= $fields[3];
            $memmory_size += $fields[4];
        }
        else {
            $new_key = $fields[2];
			unless ($memmory_size += $fields[3]){
				#print "异常行数据:",$line ,"\n";
			}
        }
        my @single_keys = split $semicolon_separator, $new_key;
        # 理论上应该是弹尾部，但是有时候不只是有一个key（可以在设计key的时候进行定义一个分隔符）
        pop(@single_keys);

        my $new_single_key = join( $semicolon_separator, @single_keys );
        # 继续判断是否包含非固定key的部分
        my @again_keys = split $semicolon_separator, $new_single_key;
        my $final_key = "";
        my $flag = "";
        foreach my $s (@again_keys) {
            # 不满足直接进行拼接新的字符串
            if ( !( $s =~ '@c.us' || $s =~ 'g.us' || $s =~ /[0-9]/ ) ) {
                $final_key .= $semicolon_separator;
                $final_key .= $s;
                $flag = "1";
            }
        }
        if(!$flag =~ "1"){
            #print "new_single_key key:",$new_key ,"\n";
            # 去除0-9、指定后缀的字符串
            my $old_key = $new_key;
            $new_key =~ s/[0-9\.us]/A/g;
            $final_key = $new_key;
            $map_keys{$final_key}= $old_key;
        }

        my $count_val = $redis_key_count_data{$final_key};
        # 计算数量以及内存大小
        if ( defined($count_val) ) {
            $redis_key_count_data{$final_key} = $count_val + 1;
        }
        else {
            $redis_key_count_data{$final_key} = 1;
        }
        my $memory_val = $redis_key_memory_data{$final_key};
        # 计算数量以及内存大小
        if (defined($memory_val)) {
            $redis_key_memory_data{$final_key} = $memory_val + $memmory_size;
        }
        else {
            $redis_key_memory_data{$final_key} = $memmory_size;
        }
    }
	my $sum_memory;
    foreach my $key ( sort { $redis_key_memory_data{$b} <=> $redis_key_memory_data{$a} } keys %redis_key_memory_data ) {
		my $value = $redis_key_memory_data{$key};
		my $conveterMemory = byteConvert($value);
		$sum_memory += $value;
    }
	my $sum_count;
    foreach my $key ( sort { $redis_key_count_data{$b} <=> $redis_key_count_data{$a} } keys %redis_key_count_data ) {
		my $value = $redis_key_count_data{$key};
		$sum_count += $value;
    }
    # 创建对象
    my $object = new Memory();
    $object->setTime($file_name);

    # perl对象存储非标量数据，使用的是引用（类似c++），要先处理成引用类型。
    my $redis_key_count_data_href = \%redis_key_count_data;
    my $redis_key_memory_data_href = \%redis_key_memory_data;
    my $map_keys_href = \%map_keys;
    $object->setKeyCountData($redis_key_count_data_href);
    $object->setKeyMemoryData($redis_key_memory_data_href);
    $object->setKeyTotalMemory($sum_memory);
    $object->setKeyTotalCount($sum_count);
    $object->setMapTotalMemoryKey($map_keys_href);
    return $object;
}
