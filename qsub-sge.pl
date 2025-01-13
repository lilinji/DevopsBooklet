#!/usr/bin/env perl

=head1 Name

qsub-sge.pl -- Enhanced SGE Job Management System

=head1 Author

Ringi (lilinji@cwbio.com.cn)
Version: 2.0.0
Last Updated: 2025-01-12

=head1 Description

An enhanced job management system for SGE (Sun Grid Engine) that provides:
- Intelligent job scheduling and monitoring
- Automatic path conversion
- Job retry mechanism
- Resource management
- Performance monitoring
- Detailed logging

=head1 Usage

  perl qsub-sge.pl <jobs.txt>
  --global          only output the global shell, but do not execute
  --queue <str>     specify the queue to use, default all.q
  --interval <num>  set interval time of checking by qstat, default 120 seconds
  --lines <num>     set number of lines to form a job, default 1
  --maxjob <num>    set the maximum number of jobs to throw out, default 100
  --convert <yes/no> convert local path to absolute path, default yes
  --secure <mark>   set the user defined job completion mark, default no need
  --reqsub          reqsub the unfinished jobs until they are finished, default no
  --resource <str>  set the required resource used in qsub -l option, default vf=1.2G
  --jobprefix <str> set the prefix tag for qsubed jobs, default work
  --verbose         output verbose information to screen
  --help            output help information to screen
  --getmem          output the memory usage information

=head1 Exmple

# 示例场景和相应的命令文件与执行方式

1. 基础示例 - 简单命令执行
-------------------------
# simple_jobs.txt
./bwa mem -t 4 ref.fa read1.fq read2.fq > aln.sam
./samtools sort -@ 4 aln.sam -o aln.sorted.bam
./samtools index aln.sorted.bam

# 执行命令
perl qsub-sge.pl --queue all.q --resource vf=4G simple_jobs.txt


2. 批量数据处理示例
-----------------
# batch_process.txt
for i in {1..10}; do
    ./fastqc -t 2 sample${i}_1.fq.gz sample${i}_2.fq.gz -o ./fastqc_results/
done
./multiqc ./fastqc_results/ -o ./multiqc_report/

# 执行命令（启用自动重试和详细日志）
perl qsub-sge.pl --queue all.q --resource vf=2G --reqsub --verbose batch_process.txt


3. 大规模并行处理
---------------
# parallel_jobs.txt
./blastn -query seq1.fa -db nt -out blast1.out -num_threads 4
./blastn -query seq2.fa -db nt -out blast2.out -num_threads 4
./blastn -query seq3.fa -db nt -out blast3.out -num_threads 4
./blastn -query seq4.fa -db nt -out blast4.out -num_threads 4
./blastn -query seq5.fa -db nt -out blast5.out -num_threads 4

# 执行命令（限制并发数和较大内存）
perl qsub-sge.pl --queue all.q --resource "vf=16G,cpu=4" --maxjob 3 --interval 300 parallel_jobs.txt


4. 混合长短作业处理
----------------
# mixed_jobs.txt
# 短作业
./fastqc sample1.fq.gz -o ./qc/
./fastqc sample2.fq.gz -o ./qc/
# 长作业
./trinity --seqType fq --left reads_1.fq --right reads_2.fq --CPU 6 --max_memory 20G
./spades.py -1 reads_1.fq -2 reads_2.fq --careful -t 8 -m 30 -o spades_output/

# 执行命令（使用不同的资源配置）
perl qsub-sge.pl --queue "all.q,big.q" --resource "vf=32G,cpu=8" --maxjob 2 --reqsub mixed_jobs.txt


5. 流程依赖处理
-------------
# pipeline_jobs.txt
# 第一阶段
./bwa index ref.fa
./bwa mem -t 4 ref.fa sample_1.fq sample_2.fq > aln.sam; samtools view -bS aln.sam > aln.bam
./samtools sort -@ 4 aln.bam -o sorted.bam; samtools index sorted.bam
# 第二阶段
./gatk HaplotypeCaller -R ref.fa -I sorted.bam -O variants.vcf
./snpEff ann -v variants.vcf > annotated.vcf

# 执行命令（使用多行合并和资源控制）
perl qsub-sge.pl --queue all.q --resource "vf=8G,cpu=4" --lines 3 --reqsub pipeline_jobs.txt


6. 后台进程处理
-------------
# background_jobs.txt
./long_running_script1.sh > log1.txt &
./long_running_script2.sh > log2.txt &
./monitor_progress.sh > monitor.log &

# 执行命令
perl qsub-sge.pl --queue all.q --resource vf=2G --interval 60 background_jobs.txt


7. 复杂数据分析流程
----------------
# analysis_pipeline.txt
# 数据预处理
./trim_galore --paired --quality 20 input_1.fq.gz input_2.fq.gz -o ./trimmed/
./fastp -i trimmed_1.fq.gz -I trimmed_2.fq.gz -o clean_1.fq.gz -O clean_2.fq.gz --json fastp.json

# 比对和变异检测
./bwa mem -t 8 ref.fa clean_1.fq.gz clean_2.fq.gz | samtools sort -@ 4 -o sorted.bam
./gatk MarkDuplicates -I sorted.bam -O dedup.bam -M metrics.txt
./gatk HaplotypeCaller -R ref.fa -I dedup.bam -O raw.vcf

# 变异注释和过滤
./snpEff ann -v raw.vcf > annotated.vcf
./vcftools --vcf annotated.vcf --min-alleles 2 --max-alleles 2 --recode --out filtered

# 执行命令（完整配置）
perl qsub-sge.pl \
    --queue all.q \
    --resource "vf=16G,cpu=8" \
    --maxjob 4 \
    --interval 120 \
    --lines 3 \
    --reqsub \
    --verbose \
    --jobprefix analysis \
    analysis_pipeline.txt


8. 错误处理测试
-------------

# 执行命令（启用所有错误处理特性）
perl qsub-sge.pl \
    --queue test.q \
    --resource "vf=4G,cpu=2" \
    --maxjob 2 \
    --interval 60 \
    --reqsub \
    --secure "Job Completed Successfully" \
    --verbose \
    error_test.txt
=head1 SUPPORT

For support and bug reports, please contact:
    Ringi <lilinji@cwbio.com.cn>
	
=cut

use strict;
use warnings;
use v5.16;
use Getopt::Long;
use FindBin qw($Bin $Script);
use File::Basename qw(basename dirname);
use File::Path qw(make_path remove_tree);
use Cwd qw(abs_path);
use Time::HiRes qw(time sleep);
use POSIX qw(strftime);
use Data::Dumper;

# 版本信息
our $VERSION = '2.0.0';

# 全局变量a
our %error_counts;
my %RUNNING_JOBS;
my %JOB_STATS;
my $START_TIME = time;

# 日志级别
use constant {
    LOG_DEBUG => 1,
    LOG_INFO  => 2,
    LOG_WARN  => 3,
    LOG_ERROR => 4
};

# 错误模式匹配
my @ERROR_PATTERNS = (
    qr/GLIBCXX_3\.4\.9.*not found/,
    qr/Segmentation fault/,
    qr/Out of memory/,
    qr/Bus error/,
    qr/killed/i,
    qr/iprscan: failed/,
    qr/failed receiving gdi request/
);

# 初始化配置
sub init_config {
    my %opts = (
        'global'     => undef,
        'queue'      => 'all.q',
        'interval'   => 120,
        'lines'      => 1,
        'maxjob'     => 100,
        'convert'    => 'yes',
        'secure'     => undef,
        'reqsub'     => 0,
        'resource'   => 'vf=1.2G',
        'job_prefix' => 'work',
        'verbose'    => 0,
        'help'       => 0,
        'getmem'     => 0,
    );

    GetOptions(
        'global'       => \$opts{global},
        'queue=s'      => \$opts{queue},
        'interval=i'   => \$opts{interval},
        'lines=i'      => \$opts{lines},
        'maxjob=i'     => \$opts{maxjob},
        'convert=s'    => \$opts{convert},
        'secure=s'     => \$opts{secure},
        'reqsub'       => \$opts{reqsub},
        'resource=s'   => \$opts{resource},
        'job_prefix=s' => \$opts{job_prefix},
        'verbose'      => \$opts{verbose},
        'help|h'       => \$opts{help},
        'getmem'       => \$opts{getmem},
    ) or usage();

    usage() if $opts{help} || !@ARGV;
    validate_config(\%opts);

    return \%opts;
}

# 配置验证
sub validate_config {
    my ($opts) = @_;

    die "Invalid interval value (must be >= 10)" if $opts->{interval} < 10;
    die "Invalid maxjob value (must be >= 1)" if $opts->{maxjob} < 1;
    die "Invalid lines value (must be >= 1)" if $opts->{lines} < 1;
    die "Invalid queue name" unless $opts->{queue} =~ /^[\w\.-]+$/;
    die "Invalid resource specification" unless $opts->{resource} =~ /^[\w\=\,\.-]+$/;
}

# 日志系统
{
    my $LOG_LEVEL = LOG_INFO;
    my $LOG_FILE;
    my $DEFAULT_LOG = "qsub-sge.default.log";

    sub init_logger {
        my ($file, $verbose) = @_;
        
        # 如果没有提供日志文件名，使用默认值
        $LOG_FILE = $file || $DEFAULT_LOG;
        
        # 确保日志文件所在目录存在
        my $log_dir = dirname($LOG_FILE);
        if ($log_dir ne '.' && !-d $log_dir) {
            eval {
                my $err;  # 声明错误变量
                make_path($log_dir, {
                    mode => 0755,
                    verbose => 1,
                    error => \$err  # 使用声明的错误变量
                });
                if ($err && @$err) {
                    die "Failed to create directory: " . $err->[0]->{message};
                }
            };
            if ($@) {
                warn "Failed to create log directory: $@\n";
                $LOG_FILE = $DEFAULT_LOG;  # 回退到默认日志文件
            }
        }

        $LOG_LEVEL = LOG_DEBUG if $verbose;

        # 尝试创建或打开日志文件
        eval {
            open my $fh, '>', $LOG_FILE or die "Cannot create log file: $!";
            print $fh "=== SGE Job Manager Log Started at " . localtime() . " ===\n";
            close $fh;
        };
        if ($@) {
            warn "Warning: Could not initialize log file ($LOG_FILE): $@\n";
            warn "Falling back to STDERR for logging\n";
        }
    }

    sub log_message {
        my ($level, $message) = @_;
        return if $level < $LOG_LEVEL;

        my $time = strftime("%Y-%m-%d %H:%M:%S", localtime);
        my $level_str = qw(DEBUG INFO WARN ERROR)[$level - 1];
        my $log_entry = "[$time] [$level_str] $message\n";

        # 尝试写入日志文件，如果失败则输出到STDERR
        if ($LOG_FILE) {
            eval {
                open my $fh, '>>', $LOG_FILE or die "Cannot open log file: $!";
                print $fh $log_entry;
                close $fh;
            };
            if ($@) {
                warn "Warning: Could not write to log file: $@\n";
                print STDERR $log_entry;
            }
        } else {
            print STDERR $log_entry;
        }

        # 如果是调试模式或错误消息，总是输出到STDERR
        print STDERR $log_entry if $LOG_LEVEL <= LOG_DEBUG || $level >= LOG_ERROR;
    }
}

# 路径转换
sub convert_to_absolute_path {
    my ($in_file, $out_file) = @_;
    my $current_path = abs_path(".");

    open my $in_fh, '<', $in_file or die "Cannot open input file: $!";
    open my $out_fh, '>', $out_file or die "Cannot create output file: $!";

    while (my $line = <$in_fh>) {
        chomp $line;
        my @words = split /\s+/, $line;

        for my $i (0..$#words) {
            if ($words[$i] !~ m{^/} && $words[$i] =~ m{/}) {
                $words[$i] = "$current_path/$words[$i]";
            }
            elsif ($words[$i] !~ m{/} && -f $words[$i]) {
                $words[$i] = "./$words[$i]";
            }
            elsif ($i > 0 && ($words[$i-1] eq '>' || $words[$i-1] eq '2>')) {
                $words[$i] = "./$words[$i]" unless $words[$i] =~ m{/};
            }
        }

        print $out_fh join(" ", @words), "\n";
    }

    close $in_fh;
    close $out_fh;
}
# 作业管理系统核心功能
{
    # 作业状态缓存
    my %job_status_cache;
    my $cache_timestamp = 0;
    my $CACHE_VALIDITY = 5; # 缓存有效期（秒）

    # 准备作业目录
    sub prepare_work_directory {
        my ($input_file, $pid) = @_;
        
        # 确保输入参数都有值
        $input_file ||= 'default_input';
        $pid ||= $$;  # 如果没有提供PID，使用当前进程ID
        
        # 构建工作目录名称
        my $work_dir = defined($input_file) && defined($pid) 
            ? "${input_file}.${pid}.qsub"
            : "default_work_dir.$$";
        
        # 记录详细信息
        log_message(LOG_DEBUG, "Creating work directory:");
        log_message(LOG_DEBUG, "  Input file: $input_file");
        log_message(LOG_DEBUG, "  PID: $pid");
        log_message(LOG_DEBUG, "  Work dir: $work_dir");

        # 确保工作目录存在
        if (!-d $work_dir) {
            eval {
                make_path($work_dir, {
                    mode => 0755,
                    verbose => 1,
                    error => \my $err
                });
                if ($err && @$err) {
                    die "Failed to create directory: " . $err->[0]->{message};
                }
            };
            if ($@) {
                log_message(LOG_ERROR, "Failed to create work directory: $@");
                die "Cannot create work directory $work_dir: $@";
            }
        }

        # 验证目录权限
        unless (-w $work_dir) {
            log_message(LOG_ERROR, "Work directory $work_dir is not writable");
            die "Work directory $work_dir is not writable";
        }

        log_message(LOG_INFO, "Successfully created work directory: $work_dir");
        return $work_dir;
    }

    # 解析作业文件
    sub parse_job_file {
        my ($config, $input_file, $work_dir) = @_;
        my @jobs;
        my $job_count = 0;
        my $current_job = '';

        open my $fh, '<', $input_file or die "Cannot open $input_file: $!";
        while (my $line = <$fh>) {
            chomp $line;
            next unless $line;
            $line =~ s/;\s*$//;  # 删除末尾分号
            $line =~ s/;\s*;/;/g;  # 清理多余分号

            $current_job .= $line;
            $current_job .= ' && echo This-Work-is-Completed!' unless $line =~ /&$/;
            $current_job .= "\n";

            if (++$job_count % $config->{lines} == 0) {
                push @jobs, {
                    id => sprintf("%05d", scalar(@jobs) + 1),
                    content => $current_job,
                    retry_count => 0,
                    status => 'pending'
                };
                $current_job = '';
            }
        }

        # 处理最后一个不完整的作业
        if ($current_job) {
            push @jobs, {
                id => sprintf("%05d", scalar(@jobs) + 1),
                content => $current_job,
                retry_count => 0,
                status => 'pending'
            };
        }
        close $fh;

        log_message(LOG_INFO, "Parsed " . scalar(@jobs) . " jobs from input file");
        return \@jobs;
    }

    # 创建作业脚本
    sub create_job_script {
        my ($job, $config, $work_dir) = @_;
        
        # 确保work_dir是绝对路径
        $work_dir = abs_path($work_dir);
        
        my $script_file = sprintf("%s/%s_%s.sh",
            $work_dir,
            $config->{job_prefix},
            $job->{id}
        );
        
        # 确保父目录存在
        my $script_dir = dirname($script_file);
        make_path($script_dir) unless -d $script_dir;
        
        eval {
            open my $fh, '>', $script_file or die "Cannot create $script_file: $!";
            print $fh "#!/bin/bash\n";
            print $fh "#\$ -S /bin/bash\n";
            print $fh "#\$ -cwd\n";
            print $fh "#\$ -V\n";
            print $fh "#\$ -o $work_dir\n";  # 明确指定输出目录
            print $fh "#\$ -e $work_dir\n";  # 明确指定错误输出目录
            print $fh 'echo "Job started at `date`"', "\n";
            print $fh $job->{content};
            print $fh 'echo "Job finished at `date`"', "\n";
            close $fh;
            
            chmod 0755, $script_file;
        };
        if ($@) {
            log_message(LOG_ERROR, "Failed to create job script: $@");
            return;
        }
        
        log_message(LOG_DEBUG, "Created job script: $script_file");
        return $script_file;
    }

    # 提交作业
    sub submit_job {
        my ($job, $config, $work_dir) = @_;
        
        # 确保work_dir存在且可写
        unless (-d $work_dir && -w $work_dir) {
            log_message(LOG_ERROR, "Work directory $work_dir is not accessible");
            return 0;
        }
        
        my $script_file = create_job_script($job, $config, $work_dir);
        return 0 unless $script_file;

        # 构建qsub命令，添加明确的输出路径
        my $qsub_cmd = sprintf("qsub -cwd -V -S /bin/bash -q %s -l %s -o %s -e %s %s 2>&1",
            $config->{queue},
            $config->{resource},
            $work_dir,
            $work_dir,
            $script_file
        );

        log_message(LOG_DEBUG, "Submitting job with command: $qsub_cmd");
        
        my $output = `$qsub_cmd`;
        if ($output =~ /Your job (\d+)/) {
            my $job_id = $1;
            $job->{sge_id} = $job_id;
            $job->{status} = 'running';
            $job->{submit_time} = time;
            $RUNNING_JOBS{$job_id} = $job;

            log_message(LOG_INFO, "Successfully submitted job $job_id (Script: $script_file)");
            return 1;
        } else {
            log_message(LOG_ERROR, "Failed to submit job: $output");
            return 0;
        }
    }

    # 检查作业状态
    sub check_job_status {
        my ($job_id) = @_;

        # 使用缓存减少系统调用
        if (time - $cache_timestamp < $CACHE_VALIDITY) {
            return $job_status_cache{$job_id} if exists $job_status_cache{$job_id};
        }

        # 刷新缓存
        %job_status_cache = ();
        my $qstat_output = `qstat 2>&1`;
        return 'unknown' if $qstat_output =~ /error|failed receiving/i;

        foreach my $line (split /\n/, $qstat_output) {
            if ($line =~ /^\s*(\d+)\s+[\d\.]+\s+\S+\s+\S+\s+(\w+)/) {
                $job_status_cache{$1} = $2;
            }
        }

        $cache_timestamp = time;
        return $job_status_cache{$job_id} || 'completed';
    }

    # 检查作业输出
    sub check_job_output {
        my ($job, $work_dir) = @_;
        my $job_id = $job->{sge_id};
        my $script_base = "$work_dir/$job->{job_prefix}_$job->{id}";

        # 检查输出文件
        my $output_ok = 0;
        if (open my $out_fh, '<', "$script_base.o$job_id") {
            while (my $line = <$out_fh>) {
                if ($line =~ /This-Work-is-Completed!/) {
                    $output_ok = 1;
                    last;
                }
            }
            close $out_fh;
        }

        # 检查错误文件
        my @errors;
        if (open my $err_fh, '<', "$script_base.e$job_id") {
            my $content = do { local $/; <$err_fh> };
            for my $pattern (@ERROR_PATTERNS) {
                push @errors, $pattern if $content =~ $pattern;
            }
            close $err_fh;
        }

        return ($output_ok, \@errors);
    }

    # 智能资源管理
    sub calculate_resource_requirements {
        my ($job) = @_;
        my $mem_pattern = qr/\b(\d+(?:\.\d+)?[MGT])\b/i;
        my $cpu_pattern = qr/\b(\d+)\s*(?:core|cpu|thread)s?\b/i;

        my $mem_req = '1.2G';  # 默认值
        my $cpu_req = 1;       # 默认值

        # 分析作业内容估算资源需求
        if ($job->{content} =~ $mem_pattern) {
            $mem_req = $1;
        }
        if ($job->{content} =~ $cpu_pattern) {
            $cpu_req = $1;
        }

        return {
            memory => $mem_req,
            cpu => $cpu_req
        };
    }

    # 节点健康检查
    sub check_node_health {
        my %unhealthy_nodes;

        my @qhost_output = `qhost`;
        shift @qhost_output for (1..3);  # 跳过头部

        foreach my $line (@qhost_output) {
            if ($line =~ /^(\S+)\s+.*\s+-\s+/) {
                $unhealthy_nodes{$1} = 1;
            }
        }

        return \%unhealthy_nodes;
    }
}
# 错误处理和恢复机制
{
    my %error_counts;
    my $MAX_RETRIES = 3;

    # 处理作业错误
    sub handle_job_error {
        my ($job, $errors, $config) = @_;
        my $job_id = $job->{sge_id};

        $error_counts{$job_id}++;
        my $retry_count = $error_counts{$job_id};

        log_message(LOG_WARN, "Job $job_id failed (attempt $retry_count of $MAX_RETRIES)");

        if ($retry_count >= $MAX_RETRIES) {
            log_message(LOG_ERROR, "Job $job_id failed permanently after $MAX_RETRIES attempts");
            return 0;
        }

        # 分析错误类型并调整资源
        my $new_resource = adjust_resources_for_retry($job, $errors, $config);
        $config->{resource} = $new_resource if $new_resource;

        # 重新提交作业
        sleep 10;  # 等待一段时间再重试
        return submit_job($job, $config, $job->{work_dir});
    }

    # 根据错误调整资源
    sub adjust_resources_for_retry {
        my ($job, $errors, $config) = @_;
        my $current_resource = $config->{resource};

        # 解析当前资源设置
        my %resources;
        while ($current_resource =~ /(\w+)=([^,]+)/g) {
            $resources{$1} = $2;
        }

        # 根据错误类型调整资源
        foreach my $error (@$errors) {
            if ($error =~ /Out of memory|Killed|Memory limit reached/i) {
                # 增加内存限制
                if ($resources{vf} =~ /(\d+(\.\d+)?)[MGT]/) {
                    my $current_mem = $1;
                    $resources{vf} = sprintf("%.1fG", $current_mem * 1.5);
                }
            }
            elsif ($error =~ /CPU time limit exceeded/i) {
                # 增加CPU时间限制
                if ($resources{h_rt}) {
                    $resources{h_rt} *= 1.5;
                } else {
                    $resources{h_rt} = "36:00:00";
                }
            }
        }

        # 构建新的资源字符串
        return join(",", map { "$_=$resources{$_}" } keys %resources);
    }
}

# 性能监控和统计
{
    my %job_stats;

    sub update_job_stats {
        my ($job_id, $status) = @_;
        return unless exists $RUNNING_JOBS{$job_id};

        my $job = $RUNNING_JOBS{$job_id};
        my $runtime = time - ($job->{submit_time} || time);  # 添加默认值

        $job_stats{$job_id} = {
            runtime => $runtime,
            status => $status || 'unknown',  # 添加默认状态
            retries => $error_counts{$job_id} || 0
        };
    }

    sub generate_performance_report {
        my ($config) = @_;
        
        # 初始化统计数据结构
        my %stats = (
            total_jobs      => 0,
            successful_jobs => 0,
            failed_jobs     => 0,
            retried_jobs    => 0,
            avg_runtime     => 0,
            peak_memory     => '0M',  # 设置默认值
        );
        
        # 初始化完成作业数组
        my @completed_jobs = ();
        
        # 收集统计数据
        foreach my $job_id (keys %RUNNING_JOBS) {
            my $job = $RUNNING_JOBS{$job_id};
            $stats{total_jobs}++;
            
            # 确保所有必需的字段都有默认值
            $job->{status} ||= 'unknown';
            $job->{runtime} ||= 0;
            $job->{memory_used} ||= '0M';
            $job->{retry_count} ||= 0;
            
            if ($job->{status} eq 'completed') {
                $stats{successful_jobs}++;
            } elsif ($job->{status} eq 'failed') {
                $stats{failed_jobs}++;
            }
            
            $stats{retried_jobs} += $job->{retry_count};
            push @completed_jobs, $job;
        }
        
        # 计算平均运行时间
        $stats{avg_runtime} = $stats{total_jobs} > 0 
            ? (time - ($START_TIME || time)) / $stats{total_jobs}
            : 0;

        my $report = "\nPerformance Summary:\n";
        
        if ($config->{verbose}) {
            # 详细的性能统计
            $report .= sprintf(
                "Detailed Statistics:\n" .
                "  - Total Jobs: %d\n" .
                "  - Successful Jobs: %d\n" .
                "  - Failed Jobs: %d\n" .
                "  - Retried Jobs: %d\n" .
                "  - Average Runtime: %.2f minutes\n" .
                "  - Peak Memory Usage: %s\n" .
                "  - Total Runtime: %.2f minutes\n",
                $stats{total_jobs},
                $stats{successful_jobs},
                $stats{failed_jobs},
                $stats{retried_jobs},
                $stats{avg_runtime} / 60,
                $stats{peak_memory},
                (time - ($START_TIME || time)) / 60
            );
            
            # 添加每个作业的详细信息
            if (@completed_jobs) {
                $report .= "\nDetailed Job Information:\n";
                foreach my $job (@completed_jobs) {
                    $report .= sprintf(
                        "Job %s:\n" .
                        "  - Status: %s\n" .
                        "  - Runtime: %.2f minutes\n" .
                        "  - Memory Used: %s\n" .
                        "  - Retry Count: %d\n",
                        $job->{id} || 'unknown',
                        $job->{status} || 'unknown',
                        ($job->{runtime} || 0) / 60,
                        $job->{memory_used} || 'N/A',
                        $job->{retry_count} || 0
                    );
                }
            }
        } else {
            # 简要统计
            $report .= sprintf(
                "Total Jobs: %d (Success: %d, Failed: %d)\n" .
                "Total Runtime: %.2f minutes\n",
                $stats{total_jobs},
                $stats{successful_jobs},
                $stats{failed_jobs},
                (time - ($START_TIME || time)) / 60
            );
        }
        
        return $report;
    }
}

# 主程序逻辑
sub main {
    my $config = init_config();
    my $input_file = shift @ARGV;

    # 确保输入文件存在
    die "Input file not specified" unless $input_file;
    die "Input file '$input_file' does not exist" unless -f $input_file;

    # 获取当前进程ID
    my $pid = $$;

    # 创建工作目录
    my $work_dir = prepare_work_directory($input_file, $pid);

    # 初始化日志系统
    my $log_file = "$input_file.$pid.log";
    init_logger($log_file, $config->{verbose});

    log_message(LOG_INFO, "Starting job processing with:");
    log_message(LOG_INFO, "  Input file: $input_file");
    log_message(LOG_INFO, "  Work directory: $work_dir");
    log_message(LOG_INFO, "  Queue: $config->{queue}");
    log_message(LOG_INFO, "  Resource: $config->{resource}");

    # 初始化开始时间
    $START_TIME = time;

    # 如果没有提供输入文件，显示使用方法并退出
    unless ($input_file) {
        usage();
        exit 1;
    }

    # 处理路径转换
    my $global_file = "$input_file.$$.globle";
    if ($config->{convert} =~ /^y/i) {
        convert_to_absolute_path($input_file, $global_file);
        $input_file = $global_file;
    }

    # 如果只需要生成全局路径文件，则退出
    if ($config->{global}) {
        log_message(LOG_INFO, "Global path file generated: $global_file");
        exit 0;
    }

    # 解析作业文件
    my $jobs = parse_job_file($config, $input_file, $work_dir);

    # 主作业处理循环
    my $cycle = 1;
    while (@$jobs || %RUNNING_JOBS) {
        log_message(LOG_INFO, "Starting cycle $cycle");

        # 提交新作业
        while (@$jobs && scalar(keys %RUNNING_JOBS) < $config->{maxjob}) {
            my $job = shift @$jobs;
            $job->{work_dir} = $work_dir;

            if (submit_job($job, $config, $work_dir)) {
                log_message(LOG_DEBUG, "Job $job->{id} submitted successfully");
            } else {
                log_message(LOG_ERROR, "Failed to submit job $job->{id}");
                push @$jobs, $job if $config->{reqsub};
            }
        }

        # 检查运行中的作业
        foreach my $job_id (keys %RUNNING_JOBS) {
            my $status = check_job_status($job_id);

            if ($status eq 'completed' || $status eq 'unknown') {
                my $job = $RUNNING_JOBS{$job_id};
                my ($output_ok, $errors) = check_job_output($job, $work_dir);

                if ($output_ok && !@$errors) {
                    log_message(LOG_INFO, "Job $job_id completed successfully");
                    update_job_stats($job_id, 'completed');
                } else {
                    log_message(LOG_WARN, "Job $job_id failed with errors: " . join(", ", @$errors));
                    if ($config->{reqsub} && handle_job_error($job, $errors, $config)) {
                        # 作业重新提交，保持在运行队列中
                    } else {
                        update_job_stats($job_id, 'failed');
                    }
                }

                delete $RUNNING_JOBS{$job_id} unless $config->{reqsub};
            }
        }

        $cycle++;
        sleep $config->{interval} if %RUNNING_JOBS;
    }

    # 在主循环结束后生成报告
    if ($config->{verbose}) {
        generate_performance_report($config);
    }

    log_message(LOG_INFO, "All jobs completed. SGE Job Manager finished.");
}

# 添加更详细的使用说明函数
sub usage {
    print STDERR <<EOF;
Usage: perl qsub-sge.pl [options] <jobs.txt>

Required:
  <jobs.txt>         Input file containing commands to be executed

Options:
  --global          Only output the global shell, but do not execute
  --queue <str>     Specify the queue to use
                    Default: all.q
                    Example: --queue "all.q,big.q"

  --interval <num>  Set interval time of checking by qstat (seconds)
                    Default: 120
                    Range: 10-3600
                    Example: --interval 60

  --lines <num>     Set number of lines to form a job
                    Default: 1
                    Range: 1-1000
                    Example: --lines 5

  --maxjob <num>    Set the maximum number of jobs to throw out
                    Default: 100
                    Range: 1-1000
                    Example: --maxjob 50

  --convert <yes/no> Convert local path to absolute path
                    Default: yes
                    Values: yes, no
                    Example: --convert no

  --secure <mark>   Set the user defined job completion mark
                    Default: no need
                    Example: --secure "Job_Done"

  --reqsub          Reqsub the unfinished jobs until they are finished
                    Default: no
                    Example: --reqsub

  --resource <str>  Set the required resource used in qsub -l option
                    Default: vf=1.2G
                    Example: --resource "vf=4G,cpu=2"
                    常用值:
                      vf=1.9G   (适用于小型作业)
                      vf=4G     (适用于中型作业)
                      vf=8G     (适用于大型作业)

  --jobprefix <str> Set the prefix tag for qsubed jobs
                    Default: work
                    Example: --jobprefix myjob

  --verbose         Output verbose information to screen
                    Example: --verbose

  --help            Output help information to screen
                    Example: --help

  --getmem          Output the memory usage information
                    Example: --getmem

Examples:
  1. Basic usage:
     perl qsub-sge.pl --queue all.q input.txt

  2. Resource intensive jobs:
     perl qsub-sge.pl --queue big.q --resource "vf=8G,cpu=4" --maxjob 20 input.txt

  3. Multiple commands per job:
     perl qsub-sge.pl --lines 5 --jobprefix batch input.txt

  4. With automatic retry and monitoring:
     perl qsub-sge.pl --reqsub --verbose --interval 60 input.txt

  5. Memory usage tracking:
     perl qsub-sge.pl --getmem --verbose input.txt

  6. 生产环境推荐配置:
     perl qsub-sge.pl --queue all.q --resource vf=1.9G --maxjob 10 --lines 3 --interval 60 test.sh

Notes:
  - Use absolute paths or --convert yes for reliable file handling
  - Set appropriate --interval based on job duration
  - Use --reqsub for critical jobs that must complete
  - Monitor memory usage with --getmem for optimization
  - Use --verbose for detailed execution information

For more information and examples, see the documentation.
EOF
    exit 1;
}

# 确保全局变量正确初始化
BEGIN {
    our $VERSION = '2.0.0';
    our %error_counts = ();
    our %RUNNING_JOBS = ();
    our %JOB_STATS = ();
    our $START_TIME = time;
}

# 启动主程序
eval {
    main();
};
if ($@) {
    log_message(LOG_ERROR, "Fatal error: $@");
    exit 1;
}

__END__

=head2 使用说明

1. 基本用法
-----------
perl qsub-sge.pl [选项] <作业文件>

2. 命令行选项
-----------
必需参数：
  <作业文件>         包含要执行命令的文本文件，每行一个命令

基本选项：
  --help, -h        显示帮助信息
  --verbose         显示详细的运行信息
  --global          仅生成全局路径文件，不执行作业

队列控制：
  --queue <str>     指定要使用的队列名称
                    默认值: all.q
                    示例: --queue "all.q,big.q"

  --interval <num>  设置检查作业状态的间隔时间（秒）
                    默认值: 120
                    建议值: 60-300
                    示例: --interval 60

作业控制：
  --lines <num>     设置每个作业包含的命令行数
                    默认值: 1
                    示例: --lines 3

  --jobprefix <str> 设置作业名称前缀
                    默认值: work
                    示例: --jobprefix myjob

  --resource <str>  设置资源需求（SGE -l 参数）
                    默认值: vf=1.2G
                    示例: --resource "vf=4G,cpu=2"
                    常用值:
                      vf=1.9G   (适用于小型作业)
                      vf=4G     (适用于中型作业)
                      vf=8G     (适用于大型作业)

路径处理：
  --convert <yes/no> 是否将本地路径转换为绝对路径
                     默认值: yes
                     示例: --convert no

错误处理：
  --secure <mark>    设置用户自定义的作业完成标记
                     默认值: 无
                     示例: --secure "Job Done!"

  --reqsub          启用失败作业自动重新提交
                     默认值: 否
                     示例: --reqsub

监控选项：
  --getmem          输出内存使用情况统计

3. 输入文件格式
--------------
- 每行一个命令
- 支持使用分号(;)分隔的多个命令
- 支持后台命令(&)
- 建议使用绝对路径或./开头的相对路径

示例输入文件 (jobs.txt):
  ./program1 input1.txt > output1.txt
  ./program2 input2.txt > output2.txt; ./program3 input3.txt > output3.txt
  ./long_program input.txt > output.txt &

4. 输出文件
----------
程序会生成以下文件：
  - <input>.${PID}.globle  : 转换后的全局路径文件
  - <input>.${PID}.log     : 运行日志文件
  - <input>.${PID}.qsub/   : 作业脚本和输出目录
    |- work_00001.sh       : 作业脚本
    |- work_00001.o123     : 标准输出
    |- work_00001.e123     : 错误输出

5. 使用示例
----------
1. 最简单的用法：
   perl qsub-sge.pl jobs.txt

2. 指定队列和资源：
   perl qsub-sge.pl --queue all.q --resource vf=1.9G jobs.txt

3. 限制并发作业数和检查间隔：
   perl qsub-sge.pl --maxjob 10 --interval 60 jobs.txt

4. 合并多行命令：
   perl qsub-sge.pl --lines 3 --jobprefix batch jobs.txt

5. 启用自动重试和详细日志：
   perl qsub-sge.pl --reqsub --verbose --resource vf=4G jobs.txt

6. 生产环境推荐配置：
   perl qsub-sge.pl --queue all.q --resource vf=1.9G --maxjob 10 --interval 60 --reqsub jobs.txt

6. 注意事项
----------
1. 资源配置：
   - 合理设置 vf 值避免内存溢出
   - 大型作业建议使用更大的内存限制
   - CPU密集型任务注意指定cpu参数

2. 路径处理：
   - 建议使用绝对路径
   - 相对路径需要以./开头
   - 注意文件权限问题

3. 错误处理：
   - 使用 --reqsub 自动处理失败的作业
   - 检查日志文件排查问题
   - 注意观察错误输出文件

4. 性能优化：
   - 适当调整 --interval 值
   - 根据集群负载调整 --maxjob
   - 合理设置 --lines 合并小作业
=cut
