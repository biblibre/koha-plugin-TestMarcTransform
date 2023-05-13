package Koha::Plugin::Com::BibLibre::TestMarcTransform;

use base qw(Koha::Plugins::Base);

use Modern::Perl;

use C4::Context;
use C4::Items;
use C4::AuthoritiesMarc qw( GetAuthority );
use C4::Charset;
use MARC::Record;
use MARC::Field;
use Data::Dumper;
use utf8;
use Koha::Biblios;

my $module_unavailable = 0;
eval "use MARC::Transform; 1" or $module_unavailable = 1;
my $module_version;
unless($module_unavailable){
    $module_version="$MARC::Transform::VERSION";
}
#$module_version='0.003008';

our $VERSION = "0.1.6";
our $metadata = {
    name            => 'Test MARC::Transform',
    author          => 'Stéphane Delaune <stephane.delaune@biblibre.com>',
    date_authored   => '2019-11-22',
    date_updated    => '2023-05-12',
    minimum_version => '20.11.00.000',
    maximum_version => undef,
    version         => $VERSION,
    description     => "This plugin aims to test MARC::Transform's yaml's configuration on Koha MARC records (biblios or authorities)",
};

#mandatory
sub new {
    my ( $class, $args ) = @_;
    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;
    my $self = $class->SUPER::new($args);
    return $self;
}

# Mandatory even if does nothing
sub install {
    my ( $self, $args ) = @_;

    return 1;
}

# Mandatory even if does nothing
sub upgrade {
    my ( $self, $args ) = @_;

    return 1;
}

# Mandatory even if does nothing
sub uninstall {
    my ( $self, $args ) = @_;

    return 1;
}

#to appear in admin/tools
sub tool {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};
    if ($cgi->request_method eq 'POST') {
        return $self->run($args);
    }
    #define template file
    my $template = $self->get_template({ file => 'home.tt' });
    $template->param('module_unavailable' => $module_unavailable) if $module_unavailable;
    $template->param('module_version' => $module_version) if $module_version;
    return $self->output_html( $template->output() );
}

sub run {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};
    #define template file
    my $template = $self->get_template({ file => 'home.tt' });
    $template->param('module_version' => $module_version) if $module_version;
    $template->param('runned' => 1);
    my $error="";
    $error.="You need select biblionumber or authid to define if record is a bib or an auth record. " unless ($cgi->param('authorbib') and $cgi->param('authorbib') =~/^(biblionumber|authid)$/);
    my $yaml="";
    my %mth;
    #eval mthcontent if defined
    if($cgi->param('mthcontent')){
        eval($cgi->param('mthcontent'));
        $template->param('mthcontent' => $cgi->param('mthcontent'));
    }
    #set yaml content :
    #if local yaml file was loaded
    if ($cgi->param('yamluptype') and $cgi->param('yamluptype') eq "yamlfile"){
        $template->param('filepathtosave' => undef);
        my $fh = $cgi->upload('yamlfile');
        binmode $fh, ':encoding(UTF-8)';
        my $line;
        while ($line = <$fh>) {$yaml.=$line}
    }#else if yaml code was directly writted
    elsif($cgi->param('yamluptype') and $cgi->param('yamluptype') eq "yamlcode" and $cgi->param('yamlcode')){
        $yaml=$cgi->param('yamlcode');
    }
    $template->param('yamlrun' => $yaml) if defnonull($yaml);
    if(defnonull($error)){
        $template->param('error' => $error);
        return $self->output_html( $template->output() );
    }
    my @jobs;
    my $increc=0;
    #launch transformation with yaml for each id defined
    if(defnonull($cgi->param('recordids'))){
        foreach my $recordid(split(/[[:space:]]+/,$cgi->param('recordids'))){
            $increc++;
            my $terror="";
            my $recordbefore="";
            my $recordafter="";
            my $title="";
            my $mthreturn="";
            unless($recordid=~/^\d+$/){$terror.="record's id must be a number so '$recordid' is invalid"}
            else {
                my $record;
                #if biblio
                if($cgi->param('authorbib') eq "biblionumber"){
                    my $biblio = Koha::Biblios->find( $recordid );
                    $record = $biblio->metadata->record({ embed_items => 1 }) if $biblio;
                    unless ($record){$terror.= "No record from biblionumber ".$recordid.". ";}
                    else {
                        $title = "Biblio number ".$recordid." «".$biblio->title."»";
                    }
                }#else if authority
                elsif ($cgi->param('authorbib') eq "authid"){
                    $record = GetAuthority($recordid);
                    unless ($record){$terror.= "No record from authid ".$recordid.". ";}
                    else{
                        $title = "Authority number ".$recordid;
                    }
                }
                if(defnonull($terror)){
                    push (@jobs, {'error' => $terror, 'increc' => $increc});
                    next;
                }
                #write record content before transformation
                $recordbefore=$record->as_formatted;
                $recordbefore=~s/^LDR /_LDR «/g;
                $recordbefore=~s/\n(00\d   )  /\n$1«/g;
                $recordbefore=~s/\n(\d\d\d .. )_(\w)/\n$1\$$2 «/g;
                $recordbefore=~s/\n(       )_(\w)/\n$1\$$2 «/g;
                $recordbefore=~s/\n/»\n_/g;
                $recordbefore=~s/$/»/g;
                #exec MARC::Transform on this record with yaml and optional mth
                eval { $record = MARC::Transform->new ( $record, $yaml, \%mth ) };
                if ($@){$@=~s/\n/<br \/>/g;$terror.="An error was encountered during the transformation of the record : ".$@.". "; }
                #if mth is returned
                if(scalar(%mth)){unless(delnonalphanum(Dumper(\%mth)) eq "VAR1_defaultLUT_to_mth_"){
                    $mthreturn=deldefaultlut(Dumper(\%mth));
                }}
                #write record content after transformation
                $recordafter=$record->as_formatted;
                $recordafter=~s/^LDR /_LDR «/g;
                $recordafter=~s/\n(00\d   )  /\n$1«/g;
                $recordafter=~s/\n(\d\d\d .. )_(\w)/\n$1\$$2 «/g;
                $recordafter=~s/\n(       )_(\w)/\n$1\$$2 «/g;
                $recordafter=~s/\n/»\n_/g;
                $recordafter=~s/$/»/g;
            }
            push (@jobs, {'error' => $terror, 'recordbefore' => $recordbefore, 'recordafter' => $recordafter, 'title' => $title, 'mthreturn' => $mthreturn, 'increc' => $increc});
        }
    } else {
        $error.="You need to define record's ids ";
        $template->param('error' => $error);$template->param('runned' => 1);return $self->output_html( $template->output() );
    }
    $template->param('jobs' => \@jobs);
    ##die to display value
    #die Dumper($cgi->param('authorbib'));
    if(defnonull($error)){$template->param('error' => $error);}
    return $self->output_html( $template->output() );
}

sub delnonalphanum{
    my $str=shift;
    $str=~s/\W//g;
    return $str;
}

sub deldefaultlut{
    my $str=shift;
    $str=~s/\n *'_defaultLUT_to_mth_' => \{\},?//;
    $str=~s/\$VAR1 = \{//;
    $str=~s/\n\s+};//;
    $str=~s/\n          /\n/g;
    return $str;
}

sub defnonull { my $var = shift; defined $var and $var ne "" }

1;
