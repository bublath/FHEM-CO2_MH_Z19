package main;

use strict;
use warnings;
use Scalar::Util qw(looks_like_number);
use Data::Dumper;

my %sets = (
  "calibrate" => "textField",
  "selfCalibration" => "on,off",
  "reopen" => "textField",
 );
 
 my %gets = (
  "deviceInfo"      => "noArg",
  "update"			=> "noArg"
);


sub CO2_MH_Z19_Initialize($) {
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

  $hash->{DefFn}     = 	"CO2_MH_Z19_Define";
  $hash->{AttrFn}    = 	"CO2_MH_Z19_Attr";
  $hash->{SetFn}     = 	"CO2_MH_Z19_Set";
  $hash->{GetFn}     = 	"CO2_MH_Z19_Get";
  $hash->{AttrList}  = 	"tempOffset interval do_not_notify:1,0 ignore:1,0 showtime:1,0 ".
												"$readingFnAttributes";
}
################################### Todo: Set or Attribute for Mode? Other sets needed?
sub CO2_MH_Z19_Set($@) {					#

	my ( $hash, $name, @args ) = @_;

	### Check Args
	my $numberOfArgs  = int(@args);
	return "CO2_MH_Z19_Set: No cmd specified for set" if ( $numberOfArgs < 1 );

	my $cmd = shift @args;
	if (!exists($sets{$cmd}))  {
		my @cList;
		foreach my $k (keys %sets) {
			my $opts = undef;
			$opts = $sets{$k};

			if (defined($opts)) {
				push(@cList,$k . ':' . $opts);
			} else {
				push (@cList,$k);
			}
		}
		return "CO2_MH_Z19_Set: Unknown argument $cmd, choose one of " . join(" ", @cList);
	} # error unknown cmd handling
	
	if ( $cmd eq "update") {
		$hash->{helper}{xx}="set account";
		Log3 $hash->{NAME}, 1, "Call echo";
		system("echo test > test.txt &");
		Log3 $hash->{NAME}, 1, "Echo done";
		return undef;
	}
	if ( $cmd eq "reopen") {
		CO2_MH_Z19_Reopen($hash);
		return undef;
	}
	if ( $cmd eq "calibrate") {
		my $arg = shift @args;
		return "Type yes if you really want to start the device calibration" if !defined $arg || $arg != "yes";
		CO2_MH_Z19_Send($hash,0x87,0);
		return undef;
	}
	if ( $cmd eq "selfCalibration") {
		my $arg = shift @args;
		return if !defined $arg;
		if ($arg eq "on") {
			CO2_MH_Z19_Send($hash,0x79,0xa0);
		} elsif ($arg eq "off") {
			CO2_MH_Z19_Send($hash,0x79,0x00);
		}
		CO2_MH_Z19_DeviceInfo($hash); #Read changes back into readings
	}

	return undef;
}

sub CO2_MH_Z19_Reopen($) {
    my ($hash) = @_;
	Log3 $hash->{NAME}, 1, "Reopening serial device";
    DevIo_CloseDev($hash);
    sleep(1);
    DevIo_OpenDev( $hash, 0, "CO2_MH_Z19_DoInit" );
}

sub CO2_MH_Z19_Poll($) {
		my ($hash) = @_;
		Log3 $hash->{NAME}, 1, "Entering BlockingCall subfunction";
		sleep(10);
		return "done";
}

sub CO2_MH_Z19_GetfinishFn($) {
		my ($string) = @_;
		Log3 "CO2_MH_Z19", 1, "Entering Finish subfunction $string";
		return;
}

################################### 
sub CO2_MH_Z19_Get($@) {
	my ($hash, $name, @args) = @_;
	
	my $numberOfArgs  = int(@args);
	return "CO2_MH_Z19_Get: No cmd specified for get" if ( $numberOfArgs < 1 );

	my $cmd = shift @args;

	if (!exists($gets{$cmd}))  {
		my @cList;
		foreach my $k (keys %gets) {
			my $opts = undef;
			$opts = $gets{$k};

			if (defined($opts)) {
				push(@cList,$k . ':' . $opts);
			} else {
				push (@cList,$k);
			}
		}
		return "Signalbot_Get: Unknown argument $cmd, choose one of " . join(" ", @cList);
	} # error unknown cmd handling
	
	my $arg = shift @args;
	
	if ($cmd eq "deviceInfo") {
		return CO2_MH_Z19_DeviceInfo($hash);
		return undef;
	} elsif ($cmd eq "update") {
		CO2_MH_Z19_Send($hash,0x86,0);
		return CO2_MH_Z19_Update($hash);
		return undef;
	}

	return undef;
}

################################### 
sub CO2_MH_Z19_Attr(@) {					#
	my ($command, $name, $attr, $val) = @_;
	my $hash = $defs{$name};
	my $msg = undef;
	Log3 $hash->{NAME}, 5, $hash->{NAME}.": Attr $attr=$val"; 
	if ($attr eq 'interval') {
		if ( defined($val) ) {
			if ( looks_like_number($val) && $val >= 0) {
				RemoveInternalTimer($hash);
				InternalTimer(gettimeofday()+1, 'CO2_MH_Z19_Execute', $hash, 0) if $val>0;
			} else {
				$msg = "$hash->{NAME}: Wrong poll intervall defined. interval must be a number >= 0";
			}    
		} else {
			RemoveInternalTimer($hash);
		}
	}
	return undef;	
}

sub CO2_MH_Z19_DoInit($) {					#
    my $hash = shift;
	Log3 $hash->{NAME}, 1, "Init Co2 Sensor";
	CO2_MH_Z19_DeviceInfo($hash);
	return undef;
}

sub CO2_MH_Z19_DeviceInfo($) {					#
    my $hash = shift;
    my $name = $hash->{NAME};
	my @buf;
	
	Log3 $hash->{NAME}, 1, "Init Co2 DeviceInfo";
	CO2_MH_Z19_Send($hash,0xa0,0);
	@buf=CO2_MH_Z19_Read($hash);
	return "Error reading from device" if @buf==0;
	my $firmware=chr($buf[2]).chr($buf[3]).chr($buf[4]).chr($buf[5]);
	Log3 $hash->{NAME}, 1, "Firmware:".$firmware;
	CO2_MH_Z19_Send($hash,0x7D,0);
	@buf=CO2_MH_Z19_Read($hash);
	return "Error reading from device" if @buf==0;
	my $cal=$buf[7];
	Log3 $hash->{NAME}, 1, "Self Calibration:".(($cal==1)?'on':'off');
	CO2_MH_Z19_Send($hash,0x9B,0);
	@buf=CO2_MH_Z19_Read($hash);
	return "Error reading from device" if @buf==0;
	my $range = $buf[4]*256+$buf[5];
	Log3 $hash->{NAME}, 1, "Range:".$range;
	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, "Firmware", $firmware);
	readingsBulkUpdate($hash, "Range", $range);
	readingsBulkUpdate($hash, "SelfCalibration", (($cal==1)?'on':'off'));
	readingsEndUpdate($hash, 1);	
}

#Periodic read part 1 - request data from sensor - then wait 1 second for data to become ready
sub CO2_MH_Z19_Execute($) {
    my $hash = shift;
	CO2_MH_Z19_Send($hash,0x86,0);
	RemoveInternalTimer($hash);
	InternalTimer(gettimeofday() + 1, 'CO2_MH_Z19_ExecuteRead', $hash, 0);
}

#Periodic read part 2 - read data from sensor
sub CO2_MH_Z19_ExecuteRead($) {
    my $hash = shift;
	CO2_MH_Z19_Update($hash);
	RemoveInternalTimer($hash);
	my $pollInterval = AttrVal($hash->{NAME}, 'interval', 5)*60;
	InternalTimer(gettimeofday() + $pollInterval, 'CO2_MH_Z19_Execute', $hash, 0) if ($pollInterval > 0);
}

sub CO2_MH_Z19_Update($) {
    my $hash = shift;
	my $off=AttrVal($hash->{NAME},"tempOffset",0)-44;
	my @buf=CO2_MH_Z19_Read($hash);
	return "Error reading from device" if @buf==0;
	my $co2=$buf[2]*256+$buf[3];
	my $temp=$buf[4]+$off;
	Log3 $hash->{NAME}, 1, "Co2:".$co2." temperature:".$temp;
	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, "co2", $co2);
	readingsBulkUpdate($hash, "temperature", $temp);
	readingsEndUpdate($hash, 1);	
}

sub CO2_MH_Z19_Send($$$) {
    my $hash = shift;
    my $name = $hash->{NAME};
	my $cmd = shift;
	my $arg = shift;

	my @tx = (0xff,1,0,0,0,0,0,0);
	$tx[2]=$cmd;
	if ($cmd==0x79) { #Set selfCalibration on (0xa0) or off (0x00)
		$tx[3]=$arg;
	}
	my $checksum=0;
	for my $i (@tx) {
		$checksum+=$i;
	}
	$checksum=0xff-$checksum&0xff;
	$tx[8]=$checksum;
	my $msg=pack( 'C*', @tx);
	DevIo_SimpleWrite( $hash, $msg, 0 );
}

sub CO2_MH_Z19_Read($) {
    my $hash = shift;
    my $name = $hash->{NAME};
	my $buf = DevIo_SimpleReadWithTimeout( $hash, 1 );
	return if !defined $buf;
	my @ret = unpack( 'C*', $buf );
	return if @ret!=9;
	my $crc=pop @ret;
	my $checksum=0;
	for my $i (@ret) {
		$checksum+=$i;
	}
	$checksum=0xff-$checksum&0xff;
	return if $checksum!=$crc;
	return @ret;
}
	

################################### 
sub CO2_MH_Z19_Define($$) {			#
	my ($hash, $def) = @_;
	
	my @a = split( "[ \t][ \t]*", $def );

	if ( @a != 3 && @a != 4 ) {
        my $msg = "wrong syntax: define <name> CO2_MH_Z19 devicename";
        Log3 undef, 2, $msg;
        return $msg;
    }
	
    DevIo_CloseDev($hash);

    my $name = $a[0];
    my $dev  = $a[2];

    $hash->{DeviceName} = $dev;
    my $ret = DevIo_OpenDev( $hash, 0, "CO2_MH_Z19_DoInit" );
	
	RemoveInternalTimer($hash);
	my $pollInterval = AttrVal($hash->{NAME}, 'interval', 5)*60;
	InternalTimer(gettimeofday() + $pollInterval, 'CO2_MH_Z19_Execute', $hash, 0) if ($pollInterval > 0);
}

1;

#Todo Write update documentation

=pod
=item device
=item summary an interface to the MH-Z19 and related sensors
=item summary_DE Schnittstelle zum MH-Z19 und verwandte Sensoren

=begin html

<h3>CO2_MH_Z19</h3>
<a id="CO2_MH_Z19"></a>
<ul>
		provides an a test<br>
	<a id="CO2_MH_Z19-define"></a><br>
	<b>Define</b>
	<ul>
		define
		<br>
	</ul>

	<a id="CO2_MH_Z19-set"></a>
	<b>Set</b>
	<ul>
		<li><b>set calibrate</b><br>
			<a id="CO2_MH_Z19-set-set1"></a>
			set calibrate<br>
		</li>
		<li><b>set reopen</b><br>
			<a id="CO2_MH_Z19-set-set2"></a>
			set reopen<br>
		</li>
	</ul>

	<a id="CO2_MH_Z19-attr"></a>
	<b>Attributes</b>
	<ul>
		<br>
		<br>
	</ul>
	<br>
	<a id="CO2_MH_Z19-readings"></a>
	<b>Readings</b>
	<ul>
		<br>
	<br>
</ul>

=end html

=cut