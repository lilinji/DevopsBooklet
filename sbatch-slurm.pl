#!/usr/bin/env perl
#===============================================================================
# File: sbatch-slurm.pl
# 文件: sbatch-slurm.pl
#
# Purpose / 用途:
#   A clean, production-oriented Slurm job scaffold inspired by an SGE/qsub
#   runner. It reads a command list, generates sbatch scripts, submits jobs,
#   monitors with squeue/sacct, retries selected failures, and writes reports.
#
#   这是一个面向 Slurm 集群的干净版作业脚手架。它读取命令列表，生成 sbatch
#   脚本，提交作业，使用 squeue/sacct 监控，针对可恢复失败进行重试，并输出报告。
#
# Design / 设计:
#   - One self-contained Perl file, no non-core CPAN dependencies.
#   - Strict mode, explicit configuration, clear state machine.
#   - Chinese + English comments for handover in mixed teams.
#   - Conservative shell handling: never eval user commands.
#
#   - 单文件部署，不依赖非核心 CPAN 模块。
#   - strict 模式，显式配置，清晰状态机。
#   - 中英文双语注释，便于不同背景团队交接。
#   - 保守处理 shell 命令：绝不 eval 用户命令。
#===============================================================================

=head1 NAME / 名称

sbatch-slurm.pl - Clean bilingual Slurm job scaffold

sbatch-slurm.pl - 干净版中英文 Slurm 作业脚手架

=head1 SYNOPSIS / 用法

  perl sbatch-slurm.pl --partition cpu jobs.txt

  perl sbatch-slurm.pl \
      --partition cpu \
      --maxjob 20 \
      --interval 90 \
      --lines 1 \
      --smart-resource \
      --reqsub \
      --max-retries 3 \
      --convert no \
      jobs.txt

  perl sbatch-slurm.pl \
      --partition gpu \
      --gres gpu:1 \
      --cpus-per-task 8 \
      --mem 48G \
      --time 24:00:00 \
      jobs.txt

=head1 INPUT / 输入

The input file contains shell commands. By default each non-empty, non-comment
line becomes one Slurm job. Use --lines N to group N lines into one job.

输入文件是一组 shell 命令。默认情况下，每个非空、非注释行会变成一个 Slurm
作业。使用 --lines N 可以把 N 行命令合并为一个作业。

=head1 OUTPUT / 输出

A work directory will be created. It contains:

会创建一个工作目录，包含：

  scripts/             generated sbatch scripts / 生成的 sbatch 脚本
  logs/                stdout and stderr / 标准输出和标准错误
  state/state.jsonl    event stream / 状态事件流
  state/manifest.jsonl job manifest / 作业清单
  reports/summary.txt  human report / 人类可读报告
  reports/summary.json machine report / 机器可读报告

=head1 IMPORTANT / 重要提醒

This scaffold generates and submits shell scripts. It does not sandbox user
commands. Run only trusted commands in trusted environments.

本脚手架会生成并提交 shell 脚本，但不会隔离用户命令。请只在可信环境中执行可信命令。

=cut

use strict;
use warnings;
use v5.16;
use Getopt::Long qw(GetOptions);
Getopt::Long::Configure('no_ignore_case');
use FindBin qw($Bin $Script);
use File::Basename qw(basename dirname);
use File::Path qw(make_path);
use Cwd qw(abs_path getcwd);
use Time::HiRes qw(time sleep);
use POSIX qw(strftime);
use JSON::PP qw(encode_json decode_json);
use Text::ParseWords qw(shellwords);
use List::Util qw(max min);

our $VERSION = '4.0.0-clean-zh-en';

#-------------------------------------------------------------------------------
# Constants / 常量
#-------------------------------------------------------------------------------
use constant {
    LOG_DEBUG => 1,
    LOG_INFO  => 2,
    LOG_WARN  => 3,
    LOG_ERROR => 4,
};

# Terminal states reported by Slurm accounting.
# Slurm accounting 中常见的终止态。
my %TERMINAL_STATE = map { $_ => 1 } qw(
    BOOT_FAIL CANCELLED COMPLETED DEADLINE FAILED NODE_FAIL OUT_OF_MEMORY
    PREEMPTED REVOKED SPECIAL_EXIT TIMEOUT
);

# Successful states.
# 成功态。
my %SUCCESS_STATE = map { $_ => 1 } qw(COMPLETED);

# States that are usually worth retrying.
# 通常值得重试的状态。
my %RETRYABLE_STATE = map { $_ => 1 } qw(
    BOOT_FAIL FAILED NODE_FAIL OUT_OF_MEMORY PREEMPTED SPECIAL_EXIT TIMEOUT
);

# Error signatures in stdout/stderr.
# stdout/stderr 中的常见错误特征。
my @ERROR_SIGNATURES = (
    [ 'oom',        qr/out\s*of\s*memory|oom[-_ ]?kill|cannot allocate memory|killed\s+process/i ],
    [ 'timeout',    qr/time\s*limit|timed\s*out|walltime|deadline/i ],
    [ 'segfault',   qr/segmentation\s+fault|core\s+dumped|bus\s+error/i ],
    [ 'node',       qr/node\s+fail|slurmd|nodelist|communication\s+failure/i ],
    [ 'filesystem', qr/no\s+space\s+left|disk\s+quota|stale\s+file\s+handle|input\/output\s+error/i ],
    [ 'library',    qr/GLIBCXX_\d+\.\d+|libstdc\+\+|shared object file|cannot open shared object/i ],
    [ 'permission', qr/permission\s+denied|operation\s+not\s+permitted/i ],
    [ 'syntax',     qr/syntax\s+error|command\s+not\s+found|No such file or directory/i ],
);

# Global runtime state.
# 全局运行态。
my %ALL_JOBS;
my %RUNNING_BY_SLURM_ID;
my %COMPLETED_JOBS;
my %FAILED_JOBS;
my $START_EPOCH = time;

#===============================================================================
# Configuration / 配置
#===============================================================================
sub default_config {
    my %cfg = (
        # Compatibility with old SGE runner style.
        # 兼容旧 SGE 脚本的使用习惯。
        global          => 0,
        interval        => 120,
        lines           => 1,
        maxjob          => 100,
        convert         => 'no',
        secure          => 'This-Work-is-Completed!',
        reqsub          => 0,
        job_prefix      => 'work',
        verbose         => 0,
        help            => 0,
        getmem          => 0,

        # Slurm resources.
        # Slurm 资源参数。
        partition       => '',
        account         => '',
        qos             => '',
        time            => '24:00:00',
        mem             => '1G',
        mem_per_cpu     => '',
        cpus_per_task   => 1,
        nodes           => 1,
        ntasks          => 1,
        gres            => '',
        gpus            => '',
        constraint      => '',
        exclude         => '',
        nodelist        => '',
        dependency      => '',
        begin           => '',
        nice            => '',
        mail_user       => '',
        mail_type       => '',
        chdir           => getcwd(),
        shell           => '/bin/bash',
        sbatch_extra    => '',
        srun_prefix     => '',

        # Smart behavior.
        # 智能行为。
        smart_resource  => 0,
        profile         => 'auto',
        max_retries     => 3,
        retry_backoff   => 60,
        mem_grow        => 1.5,
        time_grow       => 1.5,
        cpus_grow       => 0,
        strict_success  => 1,
        pipefail        => 1,
        poll_jitter     => 5,
        check_tools     => 1,
        submit_only     => 0,
        dry_run         => 0,
        no_submit       => 0,
        keep_going      => 1,
        resume          => 0,
        self_test       => 0,
        print_template  => 0,

        # Paths.
        # 路径。
        workdir         => '',
        logdir          => '',
        scriptdir       => '',
        statedir        => '',
        reportdir       => '',
        state_file      => '',
        manifest_file   => '',
        summary_file    => '',
        json_summary    => '',
    );
    return \%cfg;
}

sub parse_options {
    my $cfg = default_config();

    GetOptions(
        'global'             => \$cfg->{global},
        'interval=i'         => \$cfg->{interval},
        'lines=i'            => \$cfg->{lines},
        'maxjob=i'           => \$cfg->{maxjob},
        'convert=s'          => \$cfg->{convert},
        'secure=s'           => \$cfg->{secure},
        'reqsub'             => \$cfg->{reqsub},
        'jobprefix=s'        => \$cfg->{job_prefix},
        'job-prefix=s'       => \$cfg->{job_prefix},
        'verbose'            => \$cfg->{verbose},
        'help|h'             => \$cfg->{help},
        'getmem'             => \$cfg->{getmem},

        'partition|p=s'      => \$cfg->{partition},
        'queue=s'            => \$cfg->{partition},
        'account|A=s'        => \$cfg->{account},
        'qos=s'              => \$cfg->{qos},
        'time|t=s'           => \$cfg->{time},
        'mem=s'              => \$cfg->{mem},
        'mem-per-cpu=s'      => \$cfg->{mem_per_cpu},
        'cpus-per-task|c=i'  => \$cfg->{cpus_per_task},
        'cpu=i'              => \$cfg->{cpus_per_task},
        'cpus=i'             => \$cfg->{cpus_per_task},
        'nodes|N=i'          => \$cfg->{nodes},
        'ntasks|n=i'         => \$cfg->{ntasks},
        'gres=s'             => \$cfg->{gres},
        'gpus=s'             => \$cfg->{gpus},
        'constraint|C=s'     => \$cfg->{constraint},
        'exclude=s'          => \$cfg->{exclude},
        'nodelist|w=s'       => \$cfg->{nodelist},
        'dependency|d=s'     => \$cfg->{dependency},
        'begin=s'            => \$cfg->{begin},
        'nice=s'             => \$cfg->{nice},
        'mail-user=s'        => \$cfg->{mail_user},
        'mail-type=s'        => \$cfg->{mail_type},
        'chdir=s'            => \$cfg->{chdir},
        'shell=s'            => \$cfg->{shell},
        'sbatch-extra=s'     => \$cfg->{sbatch_extra},
        'srun-prefix=s'      => \$cfg->{srun_prefix},

        'smart-resource!'    => \$cfg->{smart_resource},
        'profile=s'          => \$cfg->{profile},
        'max-retries=i'      => \$cfg->{max_retries},
        'retry-backoff=i'    => \$cfg->{retry_backoff},
        'mem-grow=f'         => \$cfg->{mem_grow},
        'time-grow=f'        => \$cfg->{time_grow},
        'cpus-grow=i'        => \$cfg->{cpus_grow},
        'strict-success!'    => \$cfg->{strict_success},
        'pipefail!'          => \$cfg->{pipefail},
        'poll-jitter=i'      => \$cfg->{poll_jitter},
        'check-tools!'       => \$cfg->{check_tools},
        'submit-only'        => \$cfg->{submit_only},
        'dry-run'            => \$cfg->{dry_run},
        'no-submit'          => \$cfg->{no_submit},
        'keep-going!'        => \$cfg->{keep_going},
        'resume'             => \$cfg->{resume},
        'self-test'          => \$cfg->{self_test},
        'print-template'     => \$cfg->{print_template},

        'workdir=s'          => \$cfg->{workdir},
        'logdir=s'           => \$cfg->{logdir},
        'state-file=s'       => \$cfg->{state_file},
    ) or usage(2);

    usage(0) if $cfg->{help};
    if ($cfg->{print_template}) {
        print_config_template();
        exit 0;
    }
    if ($cfg->{self_test}) {
        run_self_test();
        exit 0;
    }

    usage(2) unless @ARGV;
    validate_config($cfg);
    return $cfg;
}

sub validate_config {
    my ($cfg) = @_;

    die "--interval must be >= 10\n" if $cfg->{interval} < 10;
    die "--lines must be >= 1\n" if $cfg->{lines} < 1;
    die "--maxjob must be >= 1\n" if $cfg->{maxjob} < 1;
    die "--cpus-per-task must be >= 1\n" if $cfg->{cpus_per_task} < 1;
    die "--nodes must be >= 1\n" if $cfg->{nodes} < 1;
    die "--ntasks must be >= 1\n" if $cfg->{ntasks} < 1;
    die "--max-retries must be >= 0\n" if $cfg->{max_retries} < 0;
    die "--retry-backoff must be >= 0\n" if $cfg->{retry_backoff} < 0;
    die "--mem-grow must be >= 1\n" if $cfg->{mem_grow} < 1;
    die "--time-grow must be >= 1\n" if $cfg->{time_grow} < 1;

    if ($cfg->{partition} ne '' && $cfg->{partition} !~ /^[A-Za-z0-9_.:,\-]+$/) {
        die "Invalid --partition value\n";
    }
    if ($cfg->{account} ne '' && $cfg->{account} !~ /^[A-Za-z0-9_.:\-]+$/) {
        die "Invalid --account value\n";
    }
    if ($cfg->{qos} ne '' && $cfg->{qos} !~ /^[A-Za-z0-9_.:\-]+$/) {
        die "Invalid --qos value\n";
    }
    if ($cfg->{mem} ne '' && $cfg->{mem} !~ /^\d+(?:\.\d+)?[KMGTP]?$/i) {
        die "Invalid --mem value, examples: 1024M, 4G, 1T\n";
    }
    if ($cfg->{mem_per_cpu} ne '' && $cfg->{mem_per_cpu} !~ /^\d+(?:\.\d+)?[KMGTP]?$/i) {
        die "Invalid --mem-per-cpu value\n";
    }
    if ($cfg->{time} !~ /^(?:\d+-)?\d{1,2}:\d{2}:\d{2}$|^\d{1,2}:\d{2}$|^\d+$/) {
        die "Invalid --time value, examples: 60, 02:00:00, 2-00:00:00\n";
    }
    if ($cfg->{convert} !~ /^(yes|no)$/i) {
        die "--convert must be yes or no\n";
    }

    $cfg->{chdir} = abs_path($cfg->{chdir}) || $cfg->{chdir};
}

#===============================================================================
# Logging / 日志
#===============================================================================
{
    my $LOG_LEVEL = LOG_INFO;
    my $LOG_FILE  = '';

    sub logger_init {
        my ($path, $verbose) = @_;
        $LOG_LEVEL = $verbose ? LOG_DEBUG : LOG_INFO;
        $LOG_FILE = $path;
        my $dir = dirname($LOG_FILE);
        make_path($dir, { mode => 0755 }) if $dir && $dir ne '.' && !-d $dir;
        open my $fh, '>', $LOG_FILE or die "Cannot create log file $LOG_FILE: $!\n";
        print $fh "=== slurm smart runner started at " . scalar(localtime) . " ===\n";
        close $fh;
    }

    sub log_msg {
        my ($level, $message) = @_;
        return if $level < $LOG_LEVEL;
        my $time = strftime('%Y-%m-%d %H:%M:%S', localtime);
        my $name = qw(DEBUG INFO WARN ERROR)[$level - 1] || 'INFO';
        my $line = "[$time] [$name] $message\n";
        if ($LOG_FILE) {
            if (open my $fh, '>>', $LOG_FILE) {
                print $fh $line;
                close $fh;
            } else {
                print STDERR $line;
            }
        }
        print STDERR $line if $level >= LOG_WARN || $LOG_LEVEL <= LOG_DEBUG;
    }
}

#===============================================================================
# Generic helpers / 通用工具
#===============================================================================
sub now_text {
    return strftime('%Y-%m-%d %H:%M:%S', localtime);
}

sub compact_timestamp {
    return strftime('%Y%m%d_%H%M%S', localtime);
}

sub shell_quote {
    my ($s) = @_;
    return "''" unless defined $s && length $s;
    $s =~ s/'/'"'"'/g;
    return "'$s'";
}

sub write_file {
    my ($path, $content, $mode) = @_;
    my $dir = dirname($path);
    make_path($dir, { mode => 0755 }) if $dir && $dir ne '.' && !-d $dir;
    open my $fh, '>', $path or die "Cannot write $path: $!\n";
    print $fh $content;
    close $fh;
    chmod $mode, $path if defined $mode;
}

sub append_file {
    my ($path, $content) = @_;
    my $dir = dirname($path);
    make_path($dir, { mode => 0755 }) if $dir && $dir ne '.' && !-d $dir;
    open my $fh, '>>', $path or die "Cannot append $path: $!\n";
    print $fh $content;
    close $fh;
}

sub read_small_file {
    my ($path, $limit) = @_;
    return '' unless defined $path && -f $path;
    $limit ||= 1024 * 1024;
    open my $fh, '<', $path or return '';
    my $data = '';
    read($fh, $data, $limit);
    close $fh;
    return $data;
}

sub run_command {
    my ($cmd, $quiet) = @_;
    log_msg(LOG_DEBUG, "RUN $cmd") unless $quiet;
    my $out = `$cmd 2>&1`;
    my $rc = $? == -1 ? 127 : ($? >> 8);
    log_msg(LOG_DEBUG, "RC=$rc OUT=$out") if !$quiet && $rc != 0;
    return ($rc, $out);
}

sub jsonl_append {
    my ($path, $obj) = @_;
    append_file($path, encode_json($obj) . "\n");
}

sub normalize_state {
    my ($state) = @_;
    $state ||= 'UNKNOWN';
    $state =~ s/\+.*$//;
    $state =~ s/\s+.*$//;
    return uc($state);
}

sub is_terminal_state {
    my ($state) = @_;
    return $TERMINAL_STATE{ normalize_state($state) } ? 1 : 0;
}

sub is_success_state {
    my ($state) = @_;
    return $SUCCESS_STATE{ normalize_state($state) } ? 1 : 0;
}

sub is_retryable_state {
    my ($state) = @_;
    return $RETRYABLE_STATE{ normalize_state($state) } ? 1 : 0;
}

#===============================================================================
# Memory and time handling / 内存与时间处理
#===============================================================================
sub memory_to_mb {
    my ($mem) = @_;
    return 0 unless defined $mem && $mem ne '';
    if ($mem =~ /^(\d+(?:\.\d+)?)([KMGTP]?)$/i) {
        my ($value, $unit) = ($1 + 0, uc($2 || 'M'));
        return int($value / 1024) if $unit eq 'K';
        return int($value) if $unit eq 'M' || $unit eq '';
        return int($value * 1024) if $unit eq 'G';
        return int($value * 1024 * 1024) if $unit eq 'T';
        return int($value * 1024 * 1024 * 1024) if $unit eq 'P';
    }
    return 0;
}

sub mb_to_mem_string {
    my ($mb) = @_;
    $mb = int($mb || 1);
    $mb = 1 if $mb < 1;
    if ($mb >= 1024 * 1024 && $mb % (1024 * 1024) == 0) {
        return int($mb / (1024 * 1024)) . 'T';
    }
    if ($mb >= 1024 && $mb % 1024 == 0) {
        return int($mb / 1024) . 'G';
    }
    return $mb . 'M';
}

sub max_mem_string {
    my ($a, $b) = @_;
    return memory_to_mb($a) >= memory_to_mb($b) ? $a : $b;
}

sub grow_mem_string {
    my ($mem, $factor) = @_;
    my $mb = memory_to_mb($mem);
    $mb = 1024 if $mb <= 0;
    return mb_to_mem_string(int($mb * ($factor || 1.5)));
}

sub time_to_minutes {
    my ($t) = @_;
    return 0 unless defined $t && $t ne '';
    if ($t =~ /^(\d+)$/) {
        return $1 + 0;
    }
    if ($t =~ /^(\d{1,2}):(\d{2})$/) {
        return $1 * 60 + $2;
    }
    if ($t =~ /^(\d{1,2}):(\d{2}):(\d{2})$/) {
        return $1 * 60 + $2 + ($3 > 0 ? 1 : 0);
    }
    if ($t =~ /^(\d+)-(\d{1,2}):(\d{2}):(\d{2})$/) {
        return $1 * 24 * 60 + $2 * 60 + $3 + ($4 > 0 ? 1 : 0);
    }
    return 0;
}

sub minutes_to_time_string {
    my ($minutes) = @_;
    $minutes = int($minutes || 1);
    $minutes = 1 if $minutes < 1;
    my $days = int($minutes / 1440);
    $minutes -= $days * 1440;
    my $hours = int($minutes / 60);
    my $mins = $minutes % 60;
    return sprintf('%d-%02d:%02d:00', $days, $hours, $mins) if $days > 0;
    return sprintf('%02d:%02d:00', $hours, $mins);
}

sub max_time_string {
    my ($a, $b) = @_;
    return time_to_minutes($a) >= time_to_minutes($b) ? $a : $b;
}

sub grow_time_string {
    my ($time, $factor) = @_;
    my $minutes = time_to_minutes($time);
    $minutes = 60 if $minutes <= 0;
    return minutes_to_time_string(int($minutes * ($factor || 1.5)));
}

#===============================================================================
# Resource inference / 资源推断
#===============================================================================
sub infer_resources {
    my ($command, $cfg) = @_;
    my %res = (
        mem           => $cfg->{mem},
        time          => $cfg->{time},
        cpus_per_task => $cfg->{cpus_per_task},
        gres          => $cfg->{gres},
        gpus          => $cfg->{gpus},
        notes         => [],
    );

    # Detect thread options used by common tools.
    # 检测常见工具的线程参数。
    my @thread_patterns = (
        qr/(?:^|\s)(?:-t|-@|--threads?|--cpus|--CPU|--runThreadN)\s+(\d+)\b/,
        qr/(?:^|\s)(?:--num_threads|--num-thread|--num-threads)\s+(\d+)\b/,
        qr/(?:^|\s)(?:-p|--parallel)\s+(\d+)\b/,
    );
    for my $pat (@thread_patterns) {
        if ($command =~ $pat) {
            $res{cpus_per_task} = max($res{cpus_per_task}, $1 + 0);
            push @{ $res{notes} }, "thread_hint=$1";
        }
    }

    # Detect explicit memory parameters.
    # 检测显式内存参数。
    if ($command =~ /--max[_-]?memory\s+(\d+(?:\.\d+)?[MGT])/i) {
        $res{mem} = max_mem_string($res{mem}, $1);
        push @{ $res{notes} }, "max_memory=$1";
    }
    if ($command =~ /-Xmx(\d+(?:\.\d+)?[MGT])/i) {
        $res{mem} = max_mem_string($res{mem}, $1);
        push @{ $res{notes} }, "java_xmx=$1";
    }

    # Tool profiles are conservative: they only raise resources.
    # 工具画像采用保守策略：只上调资源，不主动下调。
    apply_tool_profile(\%res, $command);
    return \%res;
}

sub apply_tool_profile {
    my ($res, $cmd) = @_;

    if ($cmd =~ /\bbwa\s+mem\b/i) {
        raise_profile($res, 'bwa_mem', '4G', '12:00:00', 4);
    }
    if ($cmd =~ /\bsamtools\s+sort\b/i) {
        raise_profile($res, 'samtools_sort', '8G', '12:00:00', 4);
    }
    if ($cmd =~ /\bSTAR\b|star\s+--runThreadN/i) {
        raise_profile($res, 'star', '32G', '24:00:00', 8);
    }
    if ($cmd =~ /\bblastn\b|\bblastp\b|\bdiamond\b/i) {
        raise_profile($res, 'blast_like', '8G', '24:00:00', 4);
    }
    if ($cmd =~ /\btrinity\b/i) {
        raise_profile($res, 'trinity', '50G', '72:00:00', 8);
    }
    if ($cmd =~ /\bspades\.py\b|\bmetaspades\.py\b/i) {
        raise_profile($res, 'spades', '32G', '72:00:00', 8);
    }
    if ($cmd =~ /\bgatk\b|GenomeAnalysisTK/i) {
        raise_profile($res, 'gatk', '16G', '24:00:00', 4);
    }
    if ($cmd =~ /\bfastqc\b|\bfastp\b|\btrim_galore\b/i) {
        raise_profile($res, 'qc', '4G', '06:00:00', 2);
    }
    if ($cmd =~ /\bminimap2\b/i) {
        raise_profile($res, 'minimap2', '8G', '12:00:00', 4);
    }
    if ($cmd =~ /\bcellranger\b/i) {
        raise_profile($res, 'cellranger', '64G', '72:00:00', 16);
    }
    if ($cmd =~ /\bpython\b.*\b(torch|tensorflow|jax|cuda)\b|\btorchrun\b/i) {
        push @{ $res->{notes} }, 'gpu_hint_detected';
    }
}

sub raise_profile {
    my ($res, $name, $mem, $time, $cpus) = @_;
    $res->{mem} = max_mem_string($res->{mem}, $mem);
    $res->{time} = max_time_string($res->{time}, $time);
    $res->{cpus_per_task} = max($res->{cpus_per_task}, $cpus);
    push @{ $res->{notes} }, "profile=$name";
}

sub resources_for_job {
    my ($job, $cfg) = @_;
    my $res = {
        mem           => $cfg->{mem},
        time          => $cfg->{time},
        cpus_per_task => $cfg->{cpus_per_task},
        gres          => $cfg->{gres},
        gpus          => $cfg->{gpus},
        notes         => [],
    };

    $res = infer_resources($job->{content}, $cfg) if $cfg->{smart_resource};

    # Retry-specific resource growth is local to this job.
    # 重试资源增长只作用于当前 job，不污染全局配置。
    if (($job->{retry_count} || 0) > 0) {
        my $class = $job->{last_failure_class} || '';
        if ($class eq 'oom' || $class eq 'OUT_OF_MEMORY') {
            $res->{mem} = grow_mem_string($res->{mem}, $cfg->{mem_grow});
            push @{ $res->{notes} }, 'retry_memory_growth';
        }
        if ($class eq 'timeout' || $class eq 'TIMEOUT') {
            $res->{time} = grow_time_string($res->{time}, $cfg->{time_grow});
            push @{ $res->{notes} }, 'retry_time_growth';
        }
        if ($cfg->{cpus_grow} > 0) {
            $res->{cpus_per_task} += $cfg->{cpus_grow};
            push @{ $res->{notes} }, 'retry_cpu_growth';
        }
    }
    return $res;
}

#===============================================================================
# Safe path conversion / 保守路径转换
#===============================================================================
sub skip_path_conversion_line {
    my ($line) = @_;
    return 1 if $line =~ /[`$]/;
    return 1 if $line =~ /<<\s*\w+/;
    return 1 if $line =~ /^\s*(if|for|while|until|case|function)\b/;
    return 1 if $line =~ /\|/;
    return 0;
}

sub token_looks_like_path {
    my ($token) = @_;
    return 0 unless defined $token && length $token;
    return 0 if $token =~ /^[-;&<>|]/;
    return 0 if $token =~ /^[A-Za-z_][A-Za-z0-9_]*=/;
    return 0 if $token =~ /^[a-z][a-z0-9+.-]*:\/\//i;
    return 1 if $token =~ m{/};
    return 1 if -e $token;
    return 0;
}

sub convert_command_line_paths {
    my ($line, $base_dir) = @_;
    return $line if skip_path_conversion_line($line);
    my @words;
    eval { @words = shellwords($line); 1 } or return $line;
    return $line unless @words;

    my @converted;
    for my $w (@words) {
        if (token_looks_like_path($w) && $w !~ m{^/}) {
            $w = "$base_dir/$w";
        }
        push @converted, shell_quote($w);
    }
    return join(' ', @converted);
}

sub convert_input_file {
    my ($input, $output, $base_dir) = @_;
    open my $in, '<', $input or die "Cannot open $input: $!\n";
    open my $out, '>', $output or die "Cannot write $output: $!\n";
    while (my $line = <$in>) {
        chomp $line;
        if ($line =~ /^\s*#/ || $line =~ /^\s*$/) {
            print $out "$line\n";
        } else {
            print $out convert_command_line_paths($line, $base_dir), "\n";
        }
    }
    close $in;
    close $out;
}

#===============================================================================
# Work directory and state / 工作目录与状态
#===============================================================================
sub prepare_workdir {
    my ($cfg, $input_file) = @_;
    my $safe = basename($input_file);
    $safe =~ s/[^A-Za-z0-9_.-]+/_/g;

    my $workdir = $cfg->{workdir} || "$safe.$$\.slurm-clean";
    $workdir = "$cfg->{chdir}/$workdir" if $workdir !~ m{^/};
    $workdir = abs_path($workdir) || $workdir;

    $cfg->{workdir} = $workdir;
    $cfg->{logdir} ||= "$workdir/logs";
    $cfg->{scriptdir} = "$workdir/scripts";
    $cfg->{statedir} = "$workdir/state";
    $cfg->{reportdir} = "$workdir/reports";
    $cfg->{state_file} ||= "$cfg->{statedir}/state.jsonl";
    $cfg->{manifest_file} = "$cfg->{statedir}/manifest.jsonl";
    $cfg->{summary_file} = "$cfg->{reportdir}/summary.txt";
    $cfg->{json_summary} = "$cfg->{reportdir}/summary.json";

    for my $dir ($cfg->{workdir}, $cfg->{logdir}, $cfg->{scriptdir}, $cfg->{statedir}, $cfg->{reportdir}) {
        make_path($dir, { mode => 0755 }) unless -d $dir;
        die "Directory is not writable: $dir\n" unless -w $dir;
    }
    return $workdir;
}

sub state_event {
    my ($cfg, $event, $job, $extra) = @_;
    my %record = (
        time  => now_text(),
        event => $event,
    );
    if ($job) {
        $record{job_id} = $job->{id};
        $record{name} = $job->{name} if defined $job->{name};
        $record{slurm_id} = $job->{slurm_id} if defined $job->{slurm_id};
        $record{status} = $job->{status} if defined $job->{status};
        $record{retry_count} = $job->{retry_count} || 0;
    }
    if ($extra && ref($extra) eq 'HASH') {
        $record{$_} = $extra->{$_} for keys %$extra;
    }
    jsonl_append($cfg->{state_file}, \%record);
}

#===============================================================================
# Input parsing / 输入解析
#===============================================================================
sub parse_jobs {
    my ($cfg, $input_file) = @_;
    my @jobs;
    my @buffer;
    my $continued = '';
    my $line_no = 0;

    open my $fh, '<', $input_file or die "Cannot open $input_file: $!\n";
    while (my $line = <$fh>) {
        $line_no++;
        chomp $line;
        $line =~ s/\r$//;
        next if $line =~ /^\s*$/;
        next if $line =~ /^\s*#/;

        if ($line =~ s/\\\s*$//) {
            $continued .= $line . ' ';
            next;
        }
        $line = $continued . $line;
        $continued = '';

        push @buffer, $line;
        if (@buffer >= $cfg->{lines}) {
            push @jobs, new_job(\@buffer, scalar(@jobs) + 1, $cfg);
            @buffer = ();
        }
    }
    close $fh;

    if ($continued ne '') {
        push @buffer, $continued;
    }
    if (@buffer) {
        push @jobs, new_job(\@buffer, scalar(@jobs) + 1, $cfg);
    }

    for my $job (@jobs) {
        $ALL_JOBS{ $job->{id} } = $job;
        jsonl_append($cfg->{manifest_file}, $job);
    }

    log_msg(LOG_INFO, 'Parsed jobs: ' . scalar(@jobs));
    return \@jobs;
}

sub new_job {
    my ($lines, $index, $cfg) = @_;
    my $id = sprintf('%05d', $index);
    my $content = join("\n", @$lines);
    $content =~ s/;\s*$//;
    return {
        id           => $id,
        name         => sprintf('%s_%s', $cfg->{job_prefix}, $id),
        content      => $content,
        source_lines => [ @$lines ],
        retry_count  => 0,
        status       => 'PENDING_LOCAL',
        created_at   => now_text(),
    };
}

#===============================================================================
# Sbatch script generation / sbatch 脚本生成
#===============================================================================
sub sbatch_line {
    my ($key, $value) = @_;
    return '' unless defined $value && $value ne '';
    return "#SBATCH --$key=$value\n";
}

sub create_sbatch_script {
    my ($job, $cfg) = @_;
    my $res = resources_for_job($job, $cfg);
    $job->{resources} = $res;
    $job->{name} = sprintf('%s_%s_r%d', $cfg->{job_prefix}, $job->{id}, $job->{retry_count} || 0);

    my $script_path = "$cfg->{scriptdir}/$job->{name}.sh";
    my $stdout_t = "$cfg->{logdir}/$job->{name}.%j.out";
    my $stderr_t = "$cfg->{logdir}/$job->{name}.%j.err";
    $job->{script_path} = $script_path;
    $job->{stdout_template} = $stdout_t;
    $job->{stderr_template} = $stderr_t;

    my $script = '';
    $script .= "#!$cfg->{shell}\n";
    $script .= "# Generated by sbatch-slurm.pl\n";
    $script .= "# 由 sbatch-slurm.pl 自动生成\n";
    $script .= "# Job: $job->{name}\n";
    $script .= "# Time: " . now_text() . "\n";
    $script .= sbatch_line('job-name', $job->{name});
    $script .= sbatch_line('partition', $cfg->{partition});
    $script .= sbatch_line('account', $cfg->{account});
    $script .= sbatch_line('qos', $cfg->{qos});
    $script .= sbatch_line('chdir', $cfg->{chdir});
    $script .= sbatch_line('output', $stdout_t);
    $script .= sbatch_line('error', $stderr_t);
    $script .= sbatch_line('time', $res->{time});
    $script .= sbatch_line('nodes', $cfg->{nodes});
    $script .= sbatch_line('ntasks', $cfg->{ntasks});
    $script .= sbatch_line('cpus-per-task', $res->{cpus_per_task});
    if ($cfg->{mem_per_cpu}) {
        $script .= sbatch_line('mem-per-cpu', $cfg->{mem_per_cpu});
    } else {
        $script .= sbatch_line('mem', $res->{mem});
    }
    $script .= sbatch_line('gres', $res->{gres});
    $script .= sbatch_line('gpus', $res->{gpus});
    $script .= sbatch_line('constraint', $cfg->{constraint});
    $script .= sbatch_line('exclude', $cfg->{exclude});
    $script .= sbatch_line('nodelist', $cfg->{nodelist});
    $script .= sbatch_line('dependency', $cfg->{dependency});
    $script .= sbatch_line('begin', $cfg->{begin});
    $script .= sbatch_line('nice', $cfg->{nice});
    $script .= sbatch_line('mail-user', $cfg->{mail_user});
    $script .= sbatch_line('mail-type', $cfg->{mail_type});

    if ($cfg->{sbatch_extra}) {
        for my $extra (split /\s+/, $cfg->{sbatch_extra}) {
            next unless length $extra;
            $script .= "#SBATCH $extra\n";
        }
    }

    $script .= "\n";
    $script .= "set -Eeuo pipefail\n" if $cfg->{pipefail};
    $script .= "export SLURM_SMART_RUNNER_VERSION='$VERSION'\n";
    $script .= "export SLURM_SMART_JOB_ID='$job->{id}'\n";
    $script .= "export OMP_NUM_THREADS=\${SLURM_CPUS_PER_TASK:-$res->{cpus_per_task}}\n";
    $script .= "echo '[SMART] start time=' \$(date '+%F %T')\n";
    $script .= "echo '[SMART] host=' \$(hostname) ' slurm_job_id=' \${SLURM_JOB_ID:-NA}\n";
    $script .= "trap 'rc=\$?; echo \"[SMART] failed rc=\$rc line=\$LINENO time=\$(date +%F_%T)\"; exit \$rc' ERR\n";
    $script .= "\n# User commands begin / 用户命令开始\n";

    for my $line (split /\n/, $job->{content}) {
        next if $line =~ /^\s*$/;
        if ($cfg->{srun_prefix}) {
            $script .= "$cfg->{srun_prefix} $line\n";
        } else {
            $script .= "$line\n";
        }
    }

    $script .= "# User commands end / 用户命令结束\n";
    if (defined $cfg->{secure} && $cfg->{secure} ne '') {
        my $marker = $cfg->{secure};
        $marker =~ s/'/'"'"'/g;
        $script .= "echo '$marker'\n";
    }
    $script .= "echo '[SMART] finish time=' \$(date '+%F %T')\n";

    write_file($script_path, $script, 0755);
    return $script_path;
}

#===============================================================================
# Slurm command layer / Slurm 命令层
#===============================================================================
sub check_slurm_tools {
    my ($cfg) = @_;
    return if $cfg->{dry_run} || $cfg->{no_submit} || $cfg->{global};
    return unless $cfg->{check_tools};
    for my $tool (qw(sbatch squeue sacct sinfo scontrol)) {
        my ($rc, $out) = run_command('command -v ' . shell_quote($tool), 1);
        die "Required Slurm command not found: $tool\n" if $rc != 0;
    }
}

sub submit_job {
    my ($job, $cfg) = @_;
    my $script = create_sbatch_script($job, $cfg);

    if ($cfg->{dry_run} || $cfg->{no_submit} || $cfg->{global}) {
        $job->{slurm_id} = 'DRY' . $job->{id} . 'R' . ($job->{retry_count} || 0);
        $job->{status} = 'DRY_RUN';
        state_event($cfg, 'script_created', $job, { script => $script });
        log_msg(LOG_INFO, "Created script only: $script");
        return 1;
    }

    my ($rc, $out) = run_command('sbatch --parsable ' . shell_quote($script), 0);
    chomp $out;
    if ($rc == 0 && $out =~ /^(\d+)(?:;\S+)?/) {
        my $sid = $1;
        $job->{slurm_id} = $sid;
        $job->{status} = 'SUBMITTED';
        $job->{submitted_at} = now_text();
        $job->{stdout_path} = $job->{stdout_template};
        $job->{stderr_path} = $job->{stderr_template};
        $job->{stdout_path} =~ s/%j/$sid/g;
        $job->{stderr_path} =~ s/%j/$sid/g;
        $RUNNING_BY_SLURM_ID{$sid} = $job;
        state_event($cfg, 'submitted', $job, { output => $out });
        log_msg(LOG_INFO, "Submitted job=$job->{id} slurm_id=$sid");
        return 1;
    }

    $job->{status} = 'SUBMIT_FAILED';
    $job->{submit_error} = $out;
    state_event($cfg, 'submit_failed', $job, { output => $out, rc => $rc });
    log_msg(LOG_ERROR, "Submit failed for job=$job->{id}: $out");
    return 0;
}

sub query_squeue {
    my ($cfg, @ids) = @_;
    my %result;
    return %result unless @ids;
    return %result if $cfg->{dry_run} || $cfg->{no_submit} || $cfg->{global};

    my $id_list = join(',', @ids);
    my $format = '%i|%T|%M|%R';
    my $cmd = 'squeue -h -j ' . shell_quote($id_list) . ' -o ' . shell_quote($format);
    my ($rc, $out) = run_command($cmd, 1);
    if ($rc != 0) {
        log_msg(LOG_WARN, "squeue failed: $out");
        return %result;
    }

    for my $line (split /\n/, $out) {
        my ($id, $state, $elapsed, $reason) = split /\|/, $line, 4;
        next unless defined $id && $id ne '';
        $id =~ s/_.*$//;
        $result{$id} = {
            state   => normalize_state($state),
            elapsed => $elapsed || '',
            reason  => $reason || '',
            source  => 'squeue',
        };
    }
    return %result;
}

sub query_sacct {
    my ($cfg, $sid) = @_;
    return { state => 'UNKNOWN', source => 'disabled' } if $cfg->{dry_run} || $cfg->{no_submit} || $cfg->{global};

    my $fmt = 'JobIDRaw,State,ExitCode,Elapsed,MaxRSS,ReqMem,AllocCPUS,NNodes,NodeList,Reason';
    my $cmd = 'sacct -P -n -j ' . shell_quote($sid) . ' --format=' . shell_quote($fmt);
    my ($rc, $out) = run_command($cmd, 1);
    if ($rc != 0) {
        return { state => 'UNKNOWN', source => 'sacct_error', raw => $out };
    }

    my $best;
    for my $line (split /\n/, $out) {
        next unless $line =~ /\S/;
        my @f = split /\|/, $line, -1;
        my ($jid, $state, $exitcode, $elapsed, $maxrss, $reqmem, $alloccpus, $nnodes, $nodes, $reason) = @f;
        next unless defined $jid;
        next if $jid ne $sid && $jid =~ /\./;
        $best = {
            jobid      => $jid,
            state      => normalize_state($state),
            exitcode   => $exitcode || '',
            elapsed    => $elapsed || '',
            maxrss     => $maxrss || '',
            reqmem     => $reqmem || '',
            alloccpus  => $alloccpus || '',
            nnodes     => $nnodes || '',
            nodes      => $nodes || '',
            reason     => $reason || '',
            raw        => $line,
            source     => 'sacct',
        };
        last if $jid eq $sid;
    }
    return $best || { state => 'UNKNOWN', source => 'sacct_empty', raw => $out };
}

sub snapshot_sinfo {
    my ($cfg) = @_;
    return if $cfg->{dry_run} || $cfg->{no_submit} || $cfg->{global};
    my ($rc, $out) = run_command('sinfo -h -o ' . shell_quote('%P|%a|%l|%D|%t|%N'), 1);
    write_file("$cfg->{statedir}/sinfo.snapshot.txt", $out) if $rc == 0;
}

#===============================================================================
# Result checking and retry / 结果检查与重试
#===============================================================================
sub secure_marker_ok {
    my ($job, $cfg) = @_;
    return 1 unless $cfg->{strict_success};
    return 1 unless defined $cfg->{secure} && $cfg->{secure} ne '';
    my $out = read_small_file($job->{stdout_path}, 1024 * 1024);
    return $out =~ /\Q$cfg->{secure}\E/ ? 1 : 0;
}

sub classify_failure {
    my ($job, $acct) = @_;
    my $state = normalize_state($acct->{state} || $job->{status} || 'UNKNOWN');
    return 'oom' if $state eq 'OUT_OF_MEMORY';
    return 'timeout' if $state eq 'TIMEOUT';
    return 'node' if $state eq 'NODE_FAIL';

    my $text = '';
    $text .= read_small_file($job->{stdout_path}, 1024 * 1024) if $job->{stdout_path};
    $text .= "\n" . read_small_file($job->{stderr_path}, 1024 * 1024) if $job->{stderr_path};
    for my $sig (@ERROR_SIGNATURES) {
        my ($class, $regex) = @$sig;
        return $class if $text =~ $regex;
    }
    return lc($state || 'unknown');
}

sub maybe_retry {
    my ($job, $cfg, $acct) = @_;
    return 0 unless $cfg->{reqsub};
    return 0 if ($job->{retry_count} || 0) >= $cfg->{max_retries};

    my $state = normalize_state($acct->{state} || $job->{status} || 'UNKNOWN');
    return 0 unless is_retryable_state($state) || $state eq 'UNKNOWN';

    my $class = classify_failure($job, $acct);
    $job->{last_failure_class} = $class;
    $job->{retry_count} = ($job->{retry_count} || 0) + 1;
    $job->{status} = 'RETRY_PENDING';
    state_event($cfg, 'retry_pending', $job, { failure_class => $class });

    my $delay = $cfg->{retry_backoff} * $job->{retry_count};
    log_msg(LOG_WARN, "Retry job=$job->{id} class=$class retry=$job->{retry_count} delay=${delay}s");
    sleep($delay) if $delay > 0;
    return submit_job($job, $cfg);
}

sub finalize_job {
    my ($job, $cfg, $acct) = @_;
    my $state = normalize_state($acct->{state} || 'UNKNOWN');
    my $marker = secure_marker_ok($job, $cfg);

    if (is_success_state($state) && $marker) {
        $job->{status} = 'COMPLETED';
        $job->{finished_at} = now_text();
        $job->{accounting} = $acct;
        $COMPLETED_JOBS{ $job->{id} } = $job;
        state_event($cfg, 'completed', $job, { state => $state });
        return 'completed';
    }

    $job->{status} = is_success_state($state) && !$marker ? 'FAILED_MARKER_MISSING' : $state;
    if (maybe_retry($job, $cfg, $acct)) {
        return 'retried';
    }

    $job->{finished_at} = now_text();
    $job->{accounting} = $acct;
    $job->{failure_class} = classify_failure($job, $acct);
    $FAILED_JOBS{ $job->{id} } = $job;
    state_event($cfg, 'failed_final', $job, { failure_class => $job->{failure_class}, state => $state });
    return 'failed';
}

#===============================================================================
# Scheduler loop / 调度循环
#===============================================================================
sub process_jobs {
    my ($jobs, $cfg) = @_;
    my @pending = @$jobs;
    my $cycle = 0;

    while (@pending || %RUNNING_BY_SLURM_ID) {
        $cycle++;
        log_msg(LOG_INFO, 'cycle=' . $cycle . ' pending=' . scalar(@pending) . ' running=' . scalar(keys %RUNNING_BY_SLURM_ID));

        while (@pending && scalar(keys %RUNNING_BY_SLURM_ID) < $cfg->{maxjob}) {
            my $job = shift @pending;
            my $ok = submit_job($job, $cfg);
            if (!$ok) {
                $FAILED_JOBS{ $job->{id} } = $job;
                die "submit failed for $job->{id}\n" unless $cfg->{keep_going};
            }
            if ($cfg->{dry_run} || $cfg->{no_submit} || $cfg->{global}) {
                $COMPLETED_JOBS{ $job->{id} } = $job;
            }
        }

        last if $cfg->{dry_run} || $cfg->{no_submit} || $cfg->{global};
        last if $cfg->{submit_only} && !@pending;

        my @slurm_ids = keys %RUNNING_BY_SLURM_ID;
        my %live = query_squeue($cfg, @slurm_ids);

        for my $sid (@slurm_ids) {
            my $job = $RUNNING_BY_SLURM_ID{$sid};
            if (exists $live{$sid}) {
                $job->{status} = $live{$sid}->{state};
                $job->{last_reason} = $live{$sid}->{reason};
                state_event($cfg, 'observed_live', $job, $live{$sid});
                next;
            }

            my $acct = query_sacct($cfg, $sid);
            my $result = finalize_job($job, $cfg, $acct);
            delete $RUNNING_BY_SLURM_ID{$sid};
            log_msg(LOG_INFO, "finalized sid=$sid result=$result");
        }

        my $sleep_for = $cfg->{interval};
        $sleep_for += int(rand($cfg->{poll_jitter} + 1)) if $cfg->{poll_jitter} > 0;
        sleep($sleep_for) if @pending || %RUNNING_BY_SLURM_ID;
    }
}

#===============================================================================
# Reporting / 报告
#===============================================================================
sub generate_report {
    my ($cfg) = @_;
    my $total = scalar(keys %ALL_JOBS);
    my $ok = scalar(keys %COMPLETED_JOBS);
    my $failed = scalar(keys %FAILED_JOBS);
    my $elapsed = time - $START_EPOCH;

    my %summary = (
        version        => $VERSION,
        started_at     => strftime('%Y-%m-%d %H:%M:%S', localtime($START_EPOCH)),
        finished_at    => now_text(),
        total_jobs     => $total,
        completed_jobs => $ok,
        failed_jobs    => $failed,
        runtime_sec    => int($elapsed),
        workdir        => $cfg->{workdir},
        state_file     => $cfg->{state_file},
        manifest_file  => $cfg->{manifest_file},
    );

    my $text = '';
    $text .= "Slurm Smart Runner Clean Summary\n";
    $text .= "================================\n";
    $text .= "Version       : $VERSION\n";
    $text .= "Started       : $summary{started_at}\n";
    $text .= "Finished      : $summary{finished_at}\n";
    $text .= "Total jobs    : $total\n";
    $text .= "Completed     : $ok\n";
    $text .= "Failed        : $failed\n";
    $text .= sprintf("Runtime       : %.2f minutes\n", $elapsed / 60);
    $text .= "Workdir       : $cfg->{workdir}\n";
    $text .= "State file    : $cfg->{state_file}\n";
    $text .= "Manifest file : $cfg->{manifest_file}\n";
    $text .= "\n";

    if ($failed) {
        $text .= "Failed jobs / 失败作业\n";
        $text .= "----------------------\n";
        for my $id (sort keys %FAILED_JOBS) {
            my $j = $FAILED_JOBS{$id};
            $text .= sprintf(
                "%s slurm=%s status=%s class=%s stdout=%s stderr=%s\n",
                $id,
                $j->{slurm_id} || 'NA',
                $j->{status} || 'NA',
                $j->{failure_class} || 'NA',
                $j->{stdout_path} || 'NA',
                $j->{stderr_path} || 'NA',
            );
        }
    }

    write_file($cfg->{summary_file}, $text);
    write_file($cfg->{json_summary}, encode_json(\%summary) . "\n");
    print $text;
    return \%summary;
}

#===============================================================================
# Self-test and templates / 自检和模板
#===============================================================================
sub run_self_test {
    my @cases = (
        [ 'memory_to_mb 1G', memory_to_mb('1G') == 1024 ],
        [ 'memory_to_mb 1024M', memory_to_mb('1024M') == 1024 ],
        [ 'time_to_minutes 01:00:00', time_to_minutes('01:00:00') == 60 ],
        [ 'minutes_to_time_string', minutes_to_time_string(90) eq '01:30:00' ],
        [ 'normalize_state', normalize_state('COMPLETED+') eq 'COMPLETED' ],
    );
    my $fail = 0;
    for my $case (@cases) {
        my ($name, $ok) = @$case;
        print (($ok ? "ok" : "not ok") . " - $name\n");
        $fail++ unless $ok;
    }
    exit($fail ? 1 : 0);
}

sub print_config_template {
    print <<'EOF';
# Example command file / 示例命令文件
# Save as jobs.txt and run with sbatch-slurm.pl
# 保存为 jobs.txt，然后用 sbatch-slurm.pl 运行

echo "hello slurm" > hello.txt
hostname
sleep 5 && echo "small task finished"
EOF
}

sub usage {
    my ($exit) = @_;
    $exit = 0 unless defined $exit;
    print STDERR <<'EOF';
Usage:
  perl sbatch-slurm.pl [options] jobs.txt

Core options / 核心参数:
  --partition, -p STR       Slurm partition / Slurm 分区
  --queue STR               Compatibility alias for --partition / 兼容旧 queue 参数
  --account, -A STR         Slurm account / Slurm 账户
  --qos STR                 Slurm QoS
  --time STR                Wall time, e.g. 60, 02:00:00, 2-00:00:00 / 时间限制
  --mem STR                 Total memory, e.g. 4G / 总内存
  --mem-per-cpu STR         Memory per CPU / 每 CPU 内存
  --cpus-per-task INT       CPU threads per task / 每 task CPU 数
  --nodes INT               Node count / 节点数
  --ntasks INT              Task count / task 数
  --gres STR                Generic resource, e.g. gpu:1 / 通用资源
  --gpus STR                GPU request / GPU 申请

Job control / 作业控制:
  --lines INT               Group N command lines into one job / N 行合成一个 job
  --maxjob INT              Max concurrent submitted/running jobs / 最大并发作业
  --interval INT            Poll interval in seconds / 轮询间隔秒数
  --jobprefix STR           Job name prefix / 作业名前缀
  --secure STR              Success marker / 成功标记
  --strict-success / --no-strict-success
                            Require success marker in stdout / 是否要求成功标记

Smart behavior / 智能行为:
  --smart-resource          Infer resources from command content / 根据命令推断资源
  --reqsub                  Retry failed jobs / 失败重试
  --max-retries INT         Max retries / 最大重试次数
  --mem-grow FLOAT          Memory growth factor for OOM retry / OOM 内存增长倍数
  --time-grow FLOAT         Time growth factor for timeout retry / 超时时间增长倍数
  --cpus-grow INT           CPU increase per retry / 每次重试增加 CPU

Modes / 模式:
  --dry-run                 Generate scripts and report, do not submit / 只生成不提交
  --global                  Same style as old SGE script: generate only / 兼容旧脚本生成模式
  --submit-only             Submit and exit without monitoring / 只提交不监控
  --self-test               Run built-in unit tests / 运行内置自检
  --print-template          Print sample jobs file / 输出示例 jobs 文件

Recommended first run / 推荐首次运行:
  perl sbatch-slurm.pl --dry-run --partition cpu --convert no jobs.txt

Production example / 生产示例:
  perl sbatch-slurm.pl \
    --partition cpu \
    --maxjob 20 \
    --interval 90 \
    --smart-resource \
    --reqsub \
    --max-retries 3 \
    --convert no \
    jobs.txt
EOF
    exit $exit;
}

#===============================================================================
# Main / 主程序
#===============================================================================
sub main {
    my $cfg = parse_options();
    my $input_file = shift @ARGV;
    die "Input file not specified\n" unless $input_file;
    die "Input file not found: $input_file\n" unless -f $input_file;

    $START_EPOCH = time;
    prepare_workdir($cfg, $input_file);
    logger_init("$cfg->{logdir}/runner.log", $cfg->{verbose});
    log_msg(LOG_INFO, "version=$VERSION");
    log_msg(LOG_INFO, "input=$input_file");
    log_msg(LOG_INFO, "workdir=$cfg->{workdir}");

    check_slurm_tools($cfg);
    snapshot_sinfo($cfg);

    my $effective_input = $input_file;
    if ($cfg->{convert} =~ /^yes$/i) {
        my $converted = "$cfg->{statedir}/" . basename($input_file) . ".converted";
        convert_input_file($input_file, $converted, $cfg->{chdir});
        $effective_input = $converted;
        log_msg(LOG_INFO, "converted_input=$converted");
    }

    my $jobs = parse_jobs($cfg, $effective_input);
    process_jobs($jobs, $cfg);
    my $summary = generate_report($cfg);

    if ($cfg->{getmem}) {
        print STDERR "\nMemory hint / 内存提示:\n";
        print STDERR "  sacct -j <JOBID> --format=JobID,State,Elapsed,MaxRSS,ReqMem,AllocCPUS\n";
    }

    exit($summary->{failed_jobs} ? 2 : 0);
}

unless (caller) {
    eval { main(); 1 } or do {
        my $err = $@ || 'unknown fatal error';
        eval { log_msg(LOG_ERROR, "Fatal: $err"); 1 } or print STDERR "Fatal: $err\n";
        exit 255;
    };
}

#===============================================================================
# End of executable code. The following sections are bilingual operational notes.
# 可执行代码结束。下面是中英文运维注释，仍然属于程序文件的一部分。
#===============================================================================

=pod
=head1 BILINGUAL OPERATIONS GUIDE / 中英文运维指南

=head2 001. Architecture / 架构

# English: This section records an operational rule for architecture in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“架构”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 002. Submission / 提交

# English: This section records an operational rule for submission in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“提交”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 003. Monitoring / 监控

# English: This section records an operational rule for monitoring in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“监控”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 004. Retry / 重试

# English: This section records an operational rule for retry in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“重试”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 005. Accounting / 计费统计

# English: This section records an operational rule for accounting in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“计费统计”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 006. Logs / 日志

# English: This section records an operational rule for logs in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“日志”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 007. Security / 安全

# English: This section records an operational rule for security in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“安全”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 008. Path Handling / 路径处理

# English: This section records an operational rule for path handling in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“路径处理”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 009. Resource Inference / 资源推断

# English: This section records an operational rule for resource inference in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“资源推断”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 010. Memory / 内存

# English: This section records an operational rule for memory in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“内存”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 011. CPU / CPU

# English: This section records an operational rule for cpu in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“CPU”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 012. GPU / GPU

# English: This section records an operational rule for gpu in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“GPU”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 013. Partition / 分区

# English: This section records an operational rule for partition in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“分区”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 014. QoS / 服务质量

# English: This section records an operational rule for qos in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“服务质量”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 015. Account / 账户

# English: This section records an operational rule for account in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“账户”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 016. Dependency / 依赖

# English: This section records an operational rule for dependency in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“依赖”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 017. Failure Classification / 失败分类

# English: This section records an operational rule for failure classification in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“失败分类”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 018. Node Failure / 节点失败

# English: This section records an operational rule for node failure in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“节点失败”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 019. Timeout / 超时

# English: This section records an operational rule for timeout in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“超时”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 020. OOM / 内存溢出

# English: This section records an operational rule for oom in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“内存溢出”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 021. Filesystem / 文件系统

# English: This section records an operational rule for filesystem in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“文件系统”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 022. Fairshare / 公平共享

# English: This section records an operational rule for fairshare in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“公平共享”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 023. Backoff / 退避

# English: This section records an operational rule for backoff in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“退避”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 024. Dry Run / 试运行

# English: This section records an operational rule for dry run in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“试运行”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 025. Manifest / 清单

# English: This section records an operational rule for manifest in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“清单”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 026. State Event / 状态事件

# English: This section records an operational rule for state event in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“状态事件”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 027. Report / 报告

# English: This section records an operational rule for report in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“报告”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 028. Bioinformatics / 生物信息

# English: This section records an operational rule for bioinformatics in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“生物信息”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 029. AI Training / AI训练

# English: This section records an operational rule for ai training in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“AI训练”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 030. Data Processing / 数据处理

# English: This section records an operational rule for data processing in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“数据处理”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 031. Small Jobs / 小作业

# English: This section records an operational rule for small jobs in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“小作业”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 032. Long Jobs / 长作业

# English: This section records an operational rule for long jobs in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“长作业”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 033. Array Alternative / 数组替代

# English: This section records an operational rule for array alternative in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“数组替代”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 034. Shell Safety / Shell安全

# English: This section records an operational rule for shell safety in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“Shell安全”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 035. Environment / 环境

# English: This section records an operational rule for environment in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“环境”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 036. Containers / 容器

# English: This section records an operational rule for containers in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“容器”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 037. Modules / 模块

# English: This section records an operational rule for modules in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“模块”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 038. Conda / Conda

# English: This section records an operational rule for conda in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“Conda”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 039. Scratch / 临时目录

# English: This section records an operational rule for scratch in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“临时目录”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 040. Shared Storage / 共享存储

# English: This section records an operational rule for shared storage in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“共享存储”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 041. Debugging / 调试

# English: This section records an operational rule for debugging in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“调试”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 042. Review / 审查

# English: This section records an operational rule for review in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“审查”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 043. Production Rollout / 生产上线

# English: This section records an operational rule for production rollout in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“生产上线”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 044. Maintenance / 维护

# English: This section records an operational rule for maintenance in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“维护”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 045. Team Handover / 团队交接

# English: This section records an operational rule for team handover in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“团队交接”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 046. Audit / 审计

# English: This section records an operational rule for audit in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“审计”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 047. Capacity / 容量

# English: This section records an operational rule for capacity in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“容量”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 048. Limits / 限制

# English: This section records an operational rule for limits in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“限制”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 049. Signal Handling / 信号处理

# English: This section records an operational rule for signal handling in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“信号处理”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 050. Exit Code / 退出码

# English: This section records an operational rule for exit code in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“退出码”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 051. Success Marker / 成功标记

# English: This section records an operational rule for success marker in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“成功标记”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 052. User Experience / 用户体验

# English: This section records an operational rule for user experience in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“用户体验”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 053. Cluster Friendliness / 集群友好

# English: This section records an operational rule for cluster friendliness in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“集群友好”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 054. Versioning / 版本管理

# English: This section records an operational rule for versioning in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“版本管理”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 055. Architecture / 架构

# English: This section records an operational rule for architecture in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“架构”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 056. Submission / 提交

# English: This section records an operational rule for submission in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“提交”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 057. Monitoring / 监控

# English: This section records an operational rule for monitoring in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“监控”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 058. Retry / 重试

# English: This section records an operational rule for retry in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“重试”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 059. Accounting / 计费统计

# English: This section records an operational rule for accounting in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“计费统计”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 060. Logs / 日志

# English: This section records an operational rule for logs in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“日志”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 061. Security / 安全

# English: This section records an operational rule for security in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“安全”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 062. Path Handling / 路径处理

# English: This section records an operational rule for path handling in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“路径处理”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 063. Resource Inference / 资源推断

# English: This section records an operational rule for resource inference in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“资源推断”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 064. Memory / 内存

# English: This section records an operational rule for memory in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“内存”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 065. CPU / CPU

# English: This section records an operational rule for cpu in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“CPU”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 066. GPU / GPU

# English: This section records an operational rule for gpu in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“GPU”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 067. Partition / 分区

# English: This section records an operational rule for partition in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“分区”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 068. QoS / 服务质量

# English: This section records an operational rule for qos in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“服务质量”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 069. Account / 账户

# English: This section records an operational rule for account in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“账户”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 070. Dependency / 依赖

# English: This section records an operational rule for dependency in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“依赖”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 071. Failure Classification / 失败分类

# English: This section records an operational rule for failure classification in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“失败分类”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 072. Node Failure / 节点失败

# English: This section records an operational rule for node failure in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“节点失败”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 073. Timeout / 超时

# English: This section records an operational rule for timeout in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“超时”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 074. OOM / 内存溢出

# English: This section records an operational rule for oom in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“内存溢出”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 075. Filesystem / 文件系统

# English: This section records an operational rule for filesystem in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“文件系统”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 076. Fairshare / 公平共享

# English: This section records an operational rule for fairshare in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“公平共享”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 077. Backoff / 退避

# English: This section records an operational rule for backoff in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“退避”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 078. Dry Run / 试运行

# English: This section records an operational rule for dry run in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“试运行”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 079. Manifest / 清单

# English: This section records an operational rule for manifest in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“清单”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 080. State Event / 状态事件

# English: This section records an operational rule for state event in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“状态事件”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 081. Report / 报告

# English: This section records an operational rule for report in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“报告”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 082. Bioinformatics / 生物信息

# English: This section records an operational rule for bioinformatics in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“生物信息”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 083. AI Training / AI训练

# English: This section records an operational rule for ai training in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“AI训练”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 084. Data Processing / 数据处理

# English: This section records an operational rule for data processing in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“数据处理”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 085. Small Jobs / 小作业

# English: This section records an operational rule for small jobs in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“小作业”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 086. Long Jobs / 长作业

# English: This section records an operational rule for long jobs in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“长作业”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 087. Array Alternative / 数组替代

# English: This section records an operational rule for array alternative in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“数组替代”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 088. Shell Safety / Shell安全

# English: This section records an operational rule for shell safety in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“Shell安全”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 089. Environment / 环境

# English: This section records an operational rule for environment in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“环境”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 090. Containers / 容器

# English: This section records an operational rule for containers in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“容器”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 091. Modules / 模块

# English: This section records an operational rule for modules in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“模块”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 092. Conda / Conda

# English: This section records an operational rule for conda in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“Conda”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 093. Scratch / 临时目录

# English: This section records an operational rule for scratch in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“临时目录”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 094. Shared Storage / 共享存储

# English: This section records an operational rule for shared storage in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“共享存储”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 095. Debugging / 调试

# English: This section records an operational rule for debugging in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“调试”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 096. Review / 审查

# English: This section records an operational rule for review in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“审查”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 097. Production Rollout / 生产上线

# English: This section records an operational rule for production rollout in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“生产上线”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 098. Maintenance / 维护

# English: This section records an operational rule for maintenance in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“维护”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 099. Team Handover / 团队交接

# English: This section records an operational rule for team handover in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“团队交接”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 100. Audit / 审计

# English: This section records an operational rule for audit in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“审计”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 101. Capacity / 容量

# English: This section records an operational rule for capacity in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“容量”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 102. Limits / 限制

# English: This section records an operational rule for limits in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“限制”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 103. Signal Handling / 信号处理

# English: This section records an operational rule for signal handling in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“信号处理”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 104. Exit Code / 退出码

# English: This section records an operational rule for exit code in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“退出码”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 105. Success Marker / 成功标记

# English: This section records an operational rule for success marker in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“成功标记”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 106. User Experience / 用户体验

# English: This section records an operational rule for user experience in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“用户体验”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 107. Cluster Friendliness / 集群友好

# English: This section records an operational rule for cluster friendliness in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“集群友好”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 108. Versioning / 版本管理

# English: This section records an operational rule for versioning in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“版本管理”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 109. Architecture / 架构

# English: This section records an operational rule for architecture in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“架构”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 110. Submission / 提交

# English: This section records an operational rule for submission in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“提交”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 111. Monitoring / 监控

# English: This section records an operational rule for monitoring in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“监控”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 112. Retry / 重试

# English: This section records an operational rule for retry in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“重试”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 113. Accounting / 计费统计

# English: This section records an operational rule for accounting in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“计费统计”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 114. Logs / 日志

# English: This section records an operational rule for logs in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“日志”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 115. Security / 安全

# English: This section records an operational rule for security in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“安全”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 116. Path Handling / 路径处理

# English: This section records an operational rule for path handling in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“路径处理”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 117. Resource Inference / 资源推断

# English: This section records an operational rule for resource inference in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“资源推断”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 118. Memory / 内存

# English: This section records an operational rule for memory in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“内存”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 119. CPU / CPU

# English: This section records an operational rule for cpu in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“CPU”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 120. GPU / GPU

# English: This section records an operational rule for gpu in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“GPU”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 121. Partition / 分区

# English: This section records an operational rule for partition in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“分区”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 122. QoS / 服务质量

# English: This section records an operational rule for qos in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“服务质量”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 123. Account / 账户

# English: This section records an operational rule for account in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“账户”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 124. Dependency / 依赖

# English: This section records an operational rule for dependency in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“依赖”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 125. Failure Classification / 失败分类

# English: This section records an operational rule for failure classification in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“失败分类”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 126. Node Failure / 节点失败

# English: This section records an operational rule for node failure in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“节点失败”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 127. Timeout / 超时

# English: This section records an operational rule for timeout in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“超时”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 128. OOM / 内存溢出

# English: This section records an operational rule for oom in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“内存溢出”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 129. Filesystem / 文件系统

# English: This section records an operational rule for filesystem in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“文件系统”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 130. Fairshare / 公平共享

# English: This section records an operational rule for fairshare in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“公平共享”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 131. Backoff / 退避

# English: This section records an operational rule for backoff in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“退避”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 132. Dry Run / 试运行

# English: This section records an operational rule for dry run in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“试运行”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 133. Manifest / 清单

# English: This section records an operational rule for manifest in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“清单”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 134. State Event / 状态事件

# English: This section records an operational rule for state event in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“状态事件”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 135. Report / 报告

# English: This section records an operational rule for report in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“报告”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 136. Bioinformatics / 生物信息

# English: This section records an operational rule for bioinformatics in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“生物信息”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 137. AI Training / AI训练

# English: This section records an operational rule for ai training in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“AI训练”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 138. Data Processing / 数据处理

# English: This section records an operational rule for data processing in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“数据处理”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 139. Small Jobs / 小作业

# English: This section records an operational rule for small jobs in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“小作业”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 140. Long Jobs / 长作业

# English: This section records an operational rule for long jobs in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“长作业”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 141. Array Alternative / 数组替代

# English: This section records an operational rule for array alternative in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“数组替代”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 142. Shell Safety / Shell安全

# English: This section records an operational rule for shell safety in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“Shell安全”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 143. Environment / 环境

# English: This section records an operational rule for environment in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“环境”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 144. Containers / 容器

# English: This section records an operational rule for containers in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“容器”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 145. Modules / 模块

# English: This section records an operational rule for modules in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“模块”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 146. Conda / Conda

# English: This section records an operational rule for conda in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“Conda”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 147. Scratch / 临时目录

# English: This section records an operational rule for scratch in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“临时目录”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 148. Shared Storage / 共享存储

# English: This section records an operational rule for shared storage in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“共享存储”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 149. Debugging / 调试

# English: This section records an operational rule for debugging in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“调试”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=head2 150. Review / 审查

# English: This section records an operational rule for review in Slurm batch workflows.
# 中文：本节记录 Slurm 批处理流程中关于“审查”的运维规则。
# English: Prefer explicit configuration over hidden defaults when running production jobs.
# 中文：生产作业优先使用显式配置，不依赖隐藏默认值。
# English: Keep generated sbatch scripts because they are the final source of execution truth.
# 中文：保留生成的 sbatch 脚本，因为它们是最终执行事实来源。
# English: Use dry-run mode before the first run of a new workflow or a new partition.
# 中文：新流程或新区分首次运行前，先使用 dry-run 模式检查。
# English: Resource growth on retry must be local to the failed job, never global.
# 中文：重试资源增长必须只作用于失败作业，不能污染全局配置。
# English: A missing success marker is treated as suspicious even when Slurm says COMPLETED.
# 中文：即使 Slurm 显示 COMPLETED，缺少成功标记也应视为可疑。
# English: Monitor state events and raw logs together; neither alone is enough for forensics.
# 中文：排查问题时要同时查看状态事件和原始日志，单看任何一个都不够。
# English: Do not increase maxjob blindly; scheduler load and shared storage load matter.
# 中文：不要盲目增大 maxjob；调度器负载和共享存储负载同样重要。
# English: If a command line contains variables, pipes, loops, or here-docs, avoid automatic path conversion.
# 中文：命令行包含变量、管道、循环或 here-doc 时，避免自动路径转换。
# English: For expensive pipelines, start with maxjob=1 or maxjob=2 and scale after validation.
# 中文：昂贵流程先用 maxjob=1 或 maxjob=2 验证，再逐步扩并发。

=cut

__END__