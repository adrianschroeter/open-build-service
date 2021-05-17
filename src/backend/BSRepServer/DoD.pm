# Copyright (c) 2015 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program (see the file COPYING); if not, write to the
# Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA
#
package BSRepServer::DoD;

use Digest::SHA ();

use BSWatcher ':https';
use BSVerify;
use BSHandoff;
use BSContar;
use BSStdServer;
use BSUtil;
use BSBearer;

use BSRepServer::Containertar;
use BSRepServer::Containerinfo;

use Build;

use strict;
use warnings;

my $proxy;
$proxy = $BSConfig::proxy if defined($BSConfig::proxy);

my $maxredirects = 3;

my @binsufs = qw{rpm deb pkg.tar.gz pkg.tar.xz pkg.tar.zst};
my $binsufsre = join('|', map {"\Q$_\E"} @binsufs);

sub is_wanted_dodbinary {
  my ($pool, $p, $path, $doverify) = @_;
  my $q;
  eval { $q = Build::query($path, 'evra' => 1) };
  return 0 unless $q;
  my $data = $pool->pkg2data($p);
  $data->{'release'} = '__undef__' unless defined $data->{'release'};
  $q->{'release'} = '__undef__' unless defined $q->{'release'};
  return 0 if $data->{'name'} ne $q->{'name'} ||
	      ($data->{'arch'} || '') ne ($q->{'arch'} || '') ||
	      ($data->{'epoch'} || 0) != ($q->{'epoch'} || 0) ||
	      $data->{'version'} ne $q->{'version'} ||
	      $data->{'release'} ne $q->{'release'};
  BSVerify::verify_nevraquery($q) if $doverify;		# just in case
  return 1;
}

sub is_wanted_dodcontainer {
  my ($pool, $p, $path, $doverify) = @_;
  my $q = BSUtil::retrieve("$path.obsbinlnk", 1);
  return 0 unless $q;
  my $data = $pool->pkg2data($p);
  return 0 if $data->{'name'} ne $q->{'name'} || $data->{'version'} ne $q->{'version'};
  BSVerify::verify_nevraquery($q) if $doverify;		# just in case
  return 1;
}

sub blob_matches_digest {
  my ($tmp, $digest) = @_;
  my $ctx;
  $ctx = Digest::SHA->new($1) if $digest =~ /^sha(256|512):/;
  return 0 unless $ctx;
  my $fd;
  return 0 unless open ($fd, '<', $tmp);
  $ctx->addfile($fd);
  close($fd);
  return (split(':', $digest, 2))[1] eq $ctx->hexdigest() ? 1 : 0;
}

my %registry_authenticators;

sub doauthrpc {
  my ($param, $xmlargs, @args) = @_;
  $param = { %$param, 'resulthook' => sub { $xmlargs->($_[0]) } };
  return BSWatcher::rpc($param, $xmlargs, @args);
}

sub fetchdodcontainer {
  my ($gdst, $pool, $repo, $p, $handoff) = @_;
  my $container = $pool->pkg2name($p);
  $container =~ s/^container://;

  my $pkgname = $container;
  $pkgname =~ s/\//_/g;
  $pkgname = "_$pkgname" if $pkgname =~ /^_/;
  BSVerify::verify_filename($pkgname);
  BSVerify::verify_simple($pkgname);
  my $dir = "$gdst/:full";

  if (-e "$dir/$pkgname.obsbinlnk" && -e "$dir/$pkgname.containerinfo") {
    # package exists, why are we called? verify that it matches our expectations
    return "$dir/$pkgname.tar" if is_wanted_dodcontainer($pool, $p, "$dir/$pkgname");
  }
  # we really need to download, handoff to ajax if not already done
  BSHandoff::handoff(@$handoff) if $handoff && !$BSStdServer::isajax;

  # download all missing blobs
  my $path = $pool->pkg2path($p);
  die("bad DoD container path: $path\n") unless $path =~ /^(.*)\?(.*?)$/;
  my $regrepo = $1;
  my @blobs = split(',', $2);
  for my $blob (@blobs) {
    next if -e "$dir/_blob.$blob";
    my $tmp = "$dir/._blob.$blob.$$";
    my $url = $repo->dodurl();
    $url .= '/' unless $url =~ /\/$/;
    my $authenticator = $registry_authenticators{"$url$regrepo"};
    $authenticator = $registry_authenticators{"$url$regrepo"} = BSBearer::generate_authenticator(undef, 'verbose' => 1, 'rpccall' => \&doauthrpc) unless $authenticator;
    $url .= "v2/$regrepo/blobs/$blob";
    print "fetching: $url\n";
    my $param = {'uri' => $url, 'filename' => $tmp, 'receiver' => \&BSHTTP::file_receiver, 'proxy' => $proxy};
    $param->{'authenticator'} = $authenticator;
    $param->{'maxredirects'} = $maxredirects if defined $maxredirects;
    my $r;
    eval { $r = BSWatcher::rpc($param); };
    if ($@) {
      $@ =~ s/(\d* *)/$1$url: /;
      die($@);
    }
    return unless defined $r;
    if (!blob_matches_digest($tmp, $blob)) {
      unlink($tmp);
      die("$url: blob does not match digest\n");
    }
    rename($tmp, "$dir/_blob.$blob") || die("rename $tmp $dir/_blob.$blob: $!\n");
  }

  # delete old cruft
  unlink("$dir/$pkgname.containerinfo");
  unlink("$dir/$pkgname.obsbinlnk");

  # write containerinfo file
  my $data = $pool->pkg2data($p);
  # hack: get tags from provides
  my @tags;
  for (@{$data->{'provides' || []}}) {
    push @tags, $_ unless / = /;
  }
  push @tags, $data->{'name'} unless @tags;
  my $mtime = time();
  my @layers = @blobs;
  shift @layers;
  my $manifest = {
    'Config' => $blobs[0],
    'RepoTags' => \@tags,
    'Layers' => \@layers,
  };
  my $manifest_ent = BSContar::create_manifest_entry($manifest, $mtime);
  my $containerinfo = {
    'tar_manifest' => $manifest_ent->{'data'},
    'tar_size' => 1,	# make construct_container_tar() happy
    'tar_mtime' => $mtime,
    'tar_blobids' => \@blobs,
    'name' => $container,
    'version' => $data->{'version'},
    'tags' => \@tags,
    'file' => "$pkgname.tar",
  };
  $containerinfo->{'release'} = $data->{'release'} if defined $data->{'release'};
  my ($tar) = BSRepServer::Containertar::construct_container_tar($dir, $containerinfo);
  ($containerinfo->{'tar_md5sum'}, $containerinfo->{'tar_sha256sum'}, $containerinfo->{'tar_size'}) = BSContar::checksum_tar($tar);
  BSRepServer::Containerinfo::writecontainerinfo("$dir/.$pkgname.containerinfo", "$dir/$pkgname.containerinfo", $containerinfo);

  # write obsbinlnk file (do this last!)
  my $lnk = BSRepServer::Containerinfo::containerinfo2nevra($containerinfo);
  $lnk->{'source'} = $lnk->{'name'};
  BSVerify::verify_nevraquery($lnk);
  $lnk->{'hdrmd5'} = $containerinfo->{'tar_md5sum'};
  $lnk->{'path'} = "$pkgname.tar";
  BSUtil::store("$dir/.$pkgname.obsbinlnk", "$dir/$pkgname.obsbinlnk", $lnk);

  return "$dir/$pkgname.tar";
}

sub fetchdodbinary {
  my ($gdst, $pool, $repo, $p, $handoff) = @_;

  die($repo->name()." is no dod repo\n") unless $repo->dodurl();
  my $pkgname = $pool->pkg2name($p);
  return fetchdodcontainer($gdst, $pool, $repo, $p, $handoff) if $pkgname =~ /^container:/;
  my $path = $pool->pkg2path($p);
  die("$path has an unsupported suffix\n") unless $path =~ /\.($binsufsre)$/;
  my $suf = $1;
  if (defined(&BSSolv::pool::pkg2inmodule) && $pool->pkg2inmodule($p)) {
    $pkgname .= '-' . $pool->pkg2evr($p) . '.' . $pool->pkg2arch($p);
  }
  $pkgname .= ".$suf";
  BSVerify::verify_filename($pkgname);
  BSVerify::verify_simple($pkgname);
  my $localname = "$gdst/:full/$pkgname";
  if (-e $localname) {
    # package exists, why are we called? verify that it matches our expectations
    return $localname if is_wanted_dodbinary($pool, $p, $localname);
  }
  # we really need to download, handoff to ajax if not already done
  BSHandoff::handoff(@$handoff) if $handoff && !$BSStdServer::isajax;
  my $url = $repo->dodurl();
  $url .= '/' unless $url =~ /\/$/;
  $url .= $pool->pkg2path($p);
  my $tmp = "$gdst/:full/.dod.$$.$pkgname";
  #print "fetching: $url\n";
  my $param = {'uri' => $url, 'filename' => $tmp, 'receiver' => \&BSHTTP::file_receiver, 'proxy' => $proxy};
  $param->{'maxredirects'} = $maxredirects if defined $maxredirects;
  my $r;
  eval { $r = BSWatcher::rpc($param); };
  if ($@) {
    $@ =~ s/(\d* *)/$1$url: /;
    die($@);
  }
  return unless defined $r;
  my $checksum;
  $checksum = $pool->pkg2checksum($p) if defined &BSSolv::pool::pkg2checksum;
  eval {
    # verify the checksum if we know it
    die("checksum error for $tmp, expected $checksum\n") if $checksum && !$pool->verifypkgchecksum($p, $tmp);
    # also make sure that the evra matches what we want
    die("downloaded package is not the one we want\n") unless is_wanted_dodbinary($pool, $p, $tmp, 1);
  };
  if ($@) {
    unlink($tmp);
    die($@);
  }
  rename($tmp, $localname) || die("rename $tmp $localname: $!\n");
  return $localname;
}

1;
