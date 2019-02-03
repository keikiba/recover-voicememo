#!/usr/bin/perl
use utf8;
use Encode 'decode';
use Encode 'encode';
use strict;

use XML::SAX;
use Data::Dumper;
use File::Copy;
use File::Basename;
use Audio::M4P::QuickTime;

my $dbDir = "/data/public/Tmp/Recordings";
my $assetXml = "AssetManifest.plist";
my $dstDir = "target";
my $secUnit = "秒";

my $debug = 0;
my %files = ();

###

sub main {
    my %tgtFiles = ();
    my $asset = $dbDir . "/" . $assetXml;
    my $parser = XML::SAX::ParserFactory->parser(Handler => mySAXHandler->new);
    $parser->parse_uri($asset);

    # Create a target directory if none
    if (!-e $dstDir) {
	mkdir($dstDir) or die("can't create directory: $!");
    }

    foreach my $f (keys(%files)) {
	my $srcFile = $dbDir . "/" . $f;
	if (-e $srcFile) {

	    # Copy the file
	    print "copy \"$srcFile\" to $dstDir/\n" if $debug;
	    copy $srcFile, $dstDir or die("can't copy file: $!");

	    # Rename the file
	    my $dstFile = $files{$f}->{title} . $files{$f}->{fext};
	    my $cnt = 1;
	    while (-e "$dstDir/$dstFile") {
		$dstFile = $files{$f}->{title} . " " . sprintf("%02d", $cnt++) . $files{$f}->{fext};
	    }

	    print "rename \"$dstDir/$f\" to \"" . encode('UTF-8', "$dstDir/$dstFile") . "\"\n" if $debug;
	    rename "$dstDir/$f", "$dstDir/$dstFile";

	    # Set attributes (mtime etc.)
	    print "set utime \"" . encode('UTF-8', $dstFile) . "\" -> " . localtime($files{$f}->{mtime}) . "\n" if $debug;
	    utime(undef, $files{$f}->{mtime}, "$dstDir/$dstFile");

	    # Get M4P info
	    my $qt = new Audio::M4P::QuickTime(file => "$dstDir/$dstFile");
	    my $hashref = $qt->GetMP4Info;
	    $tgtFiles{$dstFile} = $hashref->{SECONDS};
	}
    }

    foreach my $f (keys(%tgtFiles)) {
	my ($basename, $dirname, $ext) = fileparse($f, qr/\..*$/);
	my $dstFile = $basename . " " . $tgtFiles{$f} . $secUnit . $ext;

	print "rename \"" . encode('UTF-8', "$dstDir/$f") . "\" to \"" . encode('UTF-8', "$dstDir/$dstFile") . "\"\n";
	rename "$dstDir/$f", "$dstDir/$dstFile";
    }

}
main;

package mySAXHandler;
use base qw(XML::SAX::Base);
use Time::Local;
use File::Basename;
my $isUnderKey = 0;
my $isInDict = 0;
my $toPickupData = 0;

my $curKeyFile = "";
my $curName = "";

sub start_document() {
    print "start\n" if $debug;
}
sub end_document() {
    print "end\n" if $debug;
}
sub start_element() {
    my ($self, $data) = @_;

    if (!$isInDict && !$isUnderKey && $data->{Name} =~ /^key$/) {
	$isUnderKey = 1;
	print "DICT START ...\n" . "\t" if $debug;
    }
    if ($isInDict && $data->{Name} =~ /^string$/) {
	$toPickupData = 1;
    }

    print "$data->{Name} => " if $debug;
}
sub end_element() {
    my ($self, $data) = @_;
    my ($yy, $MM, $dd, $hh, $mm, $ss);

    if ($isUnderKey && $data->{Name} =~ /^dict$/) {
	$isUnderKey = 0;
	$isInDict = 0;

	# Save data
	my ($basename, $dirname, $ext) = fileparse($curKeyFile, qr/\..*$/);
	$basename =~ /^(\d\d\d\d)(\d\d)(\d\d) (\d\d)(\d\d)(\d\d)/;
	$yy = $1 - 1900;
	$MM = $2 - 1;
	$dd = $3; $hh = $4; $mm = $5; $ss = $6;
	my $d = {
	    fname => $curKeyFile, 
	    fbase => $basename, 
	    fext  => $ext, 
	    title => $curName,
	    mtime => timelocal($ss, $mm, $hh, $dd, $MM, $yy),
	};
	$files{$curKeyFile} = $d;

	print Encode::encode('UTF-8', "DICT (fname=$d->{fname} title=$d->{title} mtime=$d->{mtime})\n") if $debug;
    }
}
sub characters {
    my ($self, $data) = @_;
    
    if ($isUnderKey && !$isInDict) {
	$curKeyFile = $data->{Data};
	$isInDict = 1;
    }
    if ($isUnderKey && $isInDict && $toPickupData) {
	$curName = $data->{Data};
	$curName =~ s/\//-/g;  # replace '/' with '-'
	$curName =~ s/:/-/g;  # replace '/' with '-'
	$toPickupData = 0;
    }
    print Encode::encode('UTF-8', $data->{Data}) if $debug;
}
