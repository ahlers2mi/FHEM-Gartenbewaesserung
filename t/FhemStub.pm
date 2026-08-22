# Minimal-Nachbau der FHEM-Laufzeit, gerade genug fuer 98_Gartenbewaesserung.
# Kernstueck ist die virtuelle Uhr: time() und gettimeofday() liefern $main::NOW,
# und advance() schiebt sie vor und feuert dabei die faelligen Timer in der
# richtigen Reihenfolge. Damit laeuft ein 20-Minuten-Ventil in Millisekunden.
package FhemStub;
BEGIN { *CORE::GLOBAL::time = sub () { int($main::NOW) }; }

package main;
use strict; use warnings;
use POSIX qw(strftime);

our (%defs, %attr, %modules, %data, %cmds, %intAt);
our $init_done = 1;
our $reread_active = 0;
our $readingFnAttributes = "event-on-change-reading event-on-update-reading";
our $NOW = 1_780_000_000;          # fester Startpunkt, kein Date::now
our @LOG;
our $TIMERSEQ = 0;
our @TIMERS;                        # {t, fn, arg, seq}

sub gettimeofday { return $main::NOW }
sub TimeNow      { return strftime("%Y-%m-%d %H:%M:%S", localtime(int($main::NOW))) }
sub FmtDateTime  { return strftime("%Y-%m-%d %H:%M:%S", localtime(int($_[0]))) }
sub time_str2num {
    my ($s) = @_;
    return 0 if(!defined($s) || $s !~ /^(\d{4})-(\d\d)-(\d\d)[ _](\d\d):(\d\d):(\d\d)/);
    require Time::Local;
    return Time::Local::timelocal($6, $5, $4, $3, $2 - 1, $1 - 1900);
}
sub Log3 { my (undef, $lvl, $txt) = @_; push @LOG, "$lvl: $txt"; return undef }
sub Log  { Log3(undef, @_) }

sub InternalTimer {
    my ($t, $fn, $arg) = @_;
    push @TIMERS, { t => $t, fn => $fn, arg => $arg, seq => $TIMERSEQ++ };
}
sub RemoveInternalTimer {
    my ($arg, $fn) = @_;
    @TIMERS = grep {
        my $keep = 1;
        if(!defined($fn)) { $keep = 0 if(($_->{arg} // '') eq ($arg // '')) }
        else { $keep = 0 if(($_->{arg} // '') eq ($arg // '') && ($_->{fn} // '') eq $fn) }
        $keep;
    } @TIMERS;
}

# Uhr vorschieben und dabei Timer feuern. Gibt die Zahl der Ausloesungen zurueck.
sub advance {
    my ($seconds) = @_;
    my $target = $main::NOW + $seconds;
    my $fired = 0;
    while(1) {
        my @due = sort { $a->{t} <=> $b->{t} || $a->{seq} <=> $b->{seq} }
                  grep { $_->{t} <= $target } @TIMERS;
        last if(!@due);
        my $n = $due[0];
        @TIMERS = grep { $_ != $n } @TIMERS;
        $main::NOW = $n->{t} if($n->{t} > $main::NOW);
        $fired++;
        die "TIMER-EXPLOSION: mehr als 20000 Ausloesungen\n" if($fired > 20000);
        my $fn = $n->{fn};
        ref($fn) eq "CODE" ? $fn->($n->{arg}) : do { no strict 'refs'; &{$fn}($n->{arg}) };
    }
    $main::NOW = $target;
    return $fired;
}

# ---- Readings / Attribute -------------------------------------------------
sub ReadingsVal {
    my ($d, $r, $def) = @_;
    return $def if(!$defs{$d} || !defined($defs{$d}{READINGS}{$r}));
    return $defs{$d}{READINGS}{$r}{VAL};
}
sub ReadingsNum {
    my ($d, $r, $def, $round) = @_;
    my $v = ReadingsVal($d, $r, $def);
    $v = ($v =~ /(-?\d+(\.\d+)?)/) ? $1 : 0;
    return $v;
}
sub ReadingsTimestamp {
    my ($d, $r, $def) = @_;
    return $def if(!$defs{$d} || !defined($defs{$d}{READINGS}{$r}));
    return $defs{$d}{READINGS}{$r}{TIME};
}
sub InternalVal { my ($d,$i,$def)=@_; return (defined($defs{$d}{$i}) ? $defs{$d}{$i} : $def) }
sub AttrVal     { my ($d,$a,$def)=@_; return (defined($attr{$d}{$a}) ? $attr{$d}{$a} : $def) }
sub AttrNum     { my ($d,$a,$def)=@_; my $v=AttrVal($d,$a,$def); return ($v=~/(-?\d+(\.\d+)?)/)?$1:0 }
sub IsDisabled  { my ($d)=@_; return (AttrVal($d,"disable",0) ? 1 : 0) }

our @EVENTS;                        # ["dev","reading: value"]
sub readingsBeginUpdate { my ($h)=@_; $h->{".u"} = []; return undef }
sub readingsBulkUpdate {
    my ($h, $r, $v) = @_;
    push @{$h->{".u"}}, [$r, $v];
    return undef;
}
sub readingsBulkUpdateIfChanged { return readingsBulkUpdate(@_) }
sub readingsEndUpdate {
    my ($h, $do) = @_;
    $h->{CHANGED} = [];
    for my $p (@{$h->{".u"} || []}) {
        my ($r, $v) = @$p;
        my $old = $h->{READINGS}{$r}{VAL};
        $h->{READINGS}{$r} = { VAL => $v, TIME => TimeNow() };
        next if(!$do);
        next if(AttrVal($h->{NAME},"event-on-change-reading","") eq ".*"
                && defined($old) && $old eq $v);
        push @EVENTS, [$h->{NAME}, "$r: $v"];
        push @{$h->{CHANGED}}, "$r: $v";
    }
    delete $h->{".u"};
    return undef;
}
sub readingsSingleUpdate {
    my ($h, $r, $v, $do) = @_;
    readingsBeginUpdate($h); readingsBulkUpdate($h, $r, $v);
    return readingsEndUpdate($h, $do);
}

sub devspec2array { my ($s)=@_; return ($defs{$s} ? ($s) : ()) }
sub deviceEvents { my ($h)=@_; return $h->{CHANGED} }
sub AnalyzeCommandChain { return fhem($_[1]) }

# Nur so viel Befehlszerleger, wie das Modul braucht: "set <dev> <reading> <wert>"
# und "set <dev> <wert>" schreiben in die Attrappe, "setreading" ebenso.
sub fhem {
    my ($cmd) = @_;
    return undef if(!defined($cmd));
    my @a = split(" ", $cmd);
    return undef if(@a < 2);
    my $verb = shift @a;
    return undef if($verb ne "set" && $verb ne "setreading");
    my $dev = shift @a;
    return undef if(!$defs{$dev});
    if(@a >= 2) { readingsSingleUpdate($defs{$dev}, $a[0], join(" ", @a[1..$#a]), 1) }
    elsif(@a == 1) { readingsSingleUpdate($defs{$dev}, "state", $a[0], 1) }
    return undef;
}
sub CommandAttr { my (undef,$p)=@_; my ($d,$a,@v)=split(" ",$p); $attr{$d}{$a}=join(" ",@v); return undef }
sub notifyRegexpChanged { return undef }
sub CommandDeleteReading { return undef }
sub HttpUtils_NonblockingGet { return undef }
1;
