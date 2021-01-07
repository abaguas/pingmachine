package Pingmachine::ProbeList;

use Any::Moose;
use Log::Any qw($log);

use Pingmachine::Probe::FPing;
use Pingmachine::Probe::SPing;
use Pingmachine::Probe::PPing;
use Pingmachine::Probe::HTTPing;
use Pingmachine::Probe::SSH;

has '_probes' => (
    isa      => 'HashRef',
    is       => 'ro',
    default  => sub { return {} },
);

has '_order2probe' => (
    isa      => 'HashRef',
    is       => 'ro',
    default  => sub { return {} },
);

# structure of _probes:
# $key => {
#            HASHREF(xxx) => { count => 1000, max => 1000, probe => HASHREF(...) },
#            HASHREF(xxx) => { count =>  234, max => 1000, probe => HASHREF(...) },
#         }

sub _find_probe_for_new_order {
    my ($self, $key) = @_;

    if(not defined $self->{_probes}{$key}) {
        $self->{_probes}{$key} = {};
    }

    for my $p (values %{$self->{_probes}{$key}}) {
        if($p->{count} < $p->{max}) {
            $p->{count}++;
            return $p->{probe};
        }
    }

    return undef;
}

sub add_order {
    my ($self, $order) = @_;

    # Create probe, if needed
    my $key = $order->probe_instance_key;
    my $probe = $self->_find_probe_for_new_order($key);
    if(not defined $probe) {
        my $probe_type = $order->probe;
        $log->debug("create new probe for key: $key");
        if($probe_type eq 'fping') {
            $probe = Pingmachine::Probe::FPing->new(
                step      => $order->step,
                pings     => $order->pings,
                interval  => $order->fping->interval || 0,
                source_ip => $order->fping->source_ip || 0,
                interface => $order->fping->interface || 0,
		ipv6      => $order->fping->ipv6 || 0,
            );
        }
        elsif($probe_type eq 'sping') {
            $probe = Pingmachine::Probe::SPing->new(
                step      => $order->step,
                pings     => $order->pings,
                interval  => $order->sping->interval || 0,
                source_ip => $order->sping->source_ip || 0,
                flags     => $order->sping->flags || '',
                interface => $order->sping->interface || 0,
		ipv6      => $order->sping->ipv6 || 0,
            );
        }
        elsif($probe_type eq 'pping') {
            $probe = Pingmachine::Probe::PPing->new(
                step      => $order->step,
                pings     => $order->pings,
                interval  => $order->pping->interval || 0,
                source_ip => $order->pping->source_ip || 0,
                flags     => $order->pping->flags || '',
                interface => $order->pping->interface || 0,
		ipv6      => $order->pping->ipv6 || 0,
            );
        }
        elsif($probe_type eq 'httping') {
            $probe = Pingmachine::Probe::HTTPing->new(
                step       => $order->step,
                pings      => $order->pings,
                interval   => $order->httping->interval || 0,
                user_agent => $order->httping->user_agent || 0,
                proxy      => $order->httping->proxy || 0,
            );
        }
        elsif($probe_type eq 'ssh') {
            $probe = Pingmachine::Probe::SSH->new(
                step => $order->step,
                pings => $order->pings,
                key_type => $order->ssh->key_type,
            );
        }
        else {
            $log->warning("unknown probe type: $probe_type");
	    return;
        }

        $self->{_probes}{$key}{$probe} = { count => 1, max => $probe->max_orders, probe => $probe };
        $probe->start();
    }

    # Add order to probe
    $probe->add_order($order);
    $self->{_order2probe}{$order} = $probe;
}

sub remove_order {
    my ($self, $order) = @_;

    # Find probe
    my $key = $order->probe_instance_key;
    my $probe = $self->{_order2probe}{$order};
    if(not defined $probe) {
        $log->warning("can't find probe for order $order");
        return;
    }

    # Remove order from probe
    $probe->remove_order_id($order->id);

    # Remove from our probe list
    if(not defined $self->{_probes}{$key}{$probe}) {
        $log->warning("can't find probe in our probe list for order $order");
    }
    else {
        my $p = $self->{_probes}{$key}{$probe};
        $p->{count}--;
        if($p->{count} <= 0) {
            delete $self->{_probes}{$key}{$probe};
        }
    }
}

__PACKAGE__->meta->make_immutable;

1;
