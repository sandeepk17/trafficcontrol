package API::Federation;
#
# Copyright 2015 Comcast Cable Communications Management, LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
#
#

# JvD Note: you always want to put Utils as the first use. Sh*t don't work if it's after the Mojo lines.
use UI::Utils;

use Mojo::Base 'Mojolicious::Controller';
use Data::Dumper;
use Net::CIDR;
use JSON;

use Data::Validate::IP qw(is_ipv4 is_ipv6);

sub index {
  my $self = shift;
  my $orderby = $self->param('orderby') || "xml_id";
  my $data;

  my $rs_data = $self->db->resultset('FederationDeliveryservice')->search(
    {},
    {   prefetch => [ 'federation', 'deliveryservice' ],
      order_by => "deliveryservice." . $orderby
    }
  );

  my $row_count = $rs_data->count();
  if ( $row_count == 0 ) {
    return $self->success( {} );
  }

  while ( my $row = $rs_data->next ) {
    my $mapping;
    $mapping->{'cname'} = $row->federation->cname;
    $mapping->{'ttl'}   = $row->federation->ttl;

    my $id        = $row->federation->id;
    my @resolvers = $self->db->resultset('FederationResolver')->search(
      { 'federation_federation_resolvers.federation' => $id },
      { prefetch => 'federation_federation_resolvers' }
    )->all();

    for my $resolver (@resolvers) {
      my $type = lc $resolver->type->name;
      if ( defined $mapping->{$type} ) {
        push( $mapping->{$type}, $resolver->ip_address );
      }
      else {
        @{ $mapping->{$type} } = ();
        push( $mapping->{$type}, $resolver->ip_address );
      }
    }

    my $xml_id = $row->deliveryservice->xml_id;
    if ( defined $data ) {
      my $ds = $self->find_delivery_service( $xml_id, $data );
      if ( !defined $ds ) {
        $data
          = $self->add_delivery_service( $xml_id, $mapping, $data );
      }
      else {
        $self->update_delivery_service( $ds, $mapping );
      }
    }
    else {
      $data = $self->add_delivery_service( $xml_id, $mapping, $data );
    }

  }
  $self->success($data);
}

sub find_delivery_service {
  my $self   = shift;
  my $xml_id = shift;
  my $data   = shift;
  my $ds;

  foreach my $service ( @{$data} ) {
    if ( $service->{'deliveryService'} eq $xml_id ) {
      $ds = $service;
    }
  }
  return $ds;
}

sub add_delivery_service {
  my $self   = shift;
  my $xml_id = shift;
  my $m      = shift;
  my $data   = shift;

  my $map;
  push( @{$map}, $m );
  push(
    @${data},
    {   "deliveryService" => $xml_id,
      "mappings"        => $map
    }
  );
  return $data;
}

sub update_delivery_service {
  my $self = shift;
  my $ds   = shift;
  my $m    = shift;

  my $map = $ds->{'mappings'};
  push( @{$map}, $m );
  $ds->{'mappings'} = $map;
}

sub add {
  my $self = shift;

  my $current_username = $self->current_user()->{username};
  my $user             = $self->find_tmuser($current_username);
  if ( !defined $user ) {
    return $self->alert(
      "You must be an Federation user to perform this operation!");
  }

  my $federations = $self->req->json->{'federations'};
  foreach my $ds ( @{$federations} ) {
    my $xml_id   = $ds->{'deliveryService'};
    my $mappings = $ds->{'mappings'};
    my $federation_id;

    foreach my $map ( @{$mappings} ) {
      my $cname = $map->{'cname'};
      my $ttl   = $map->{'ttl'};
      $federation_id = $self->add_federation( $cname, $ttl );

      my $resolve4 = $map->{'resolve4'};
      if ( defined $resolve4 ) {
        $resolve4 = $self->add_resolver( $resolve4, $federation_id,
          "resolve4" );
      }

      my $resolve6 = $map->{'resolve6'};
      if ( defined $resolve6 ) {
        $self->add_resolver( $resolve6, $federation_id, "resolve6" );
      }
    }

    $self->add_federation_deliveryservice( $federation_id, $xml_id );
  }

  $self->success( {} );
}

sub find_tmuser {
  my $self             = shift;
  my $current_username = shift;

  my $tm_user
    = $self->db->resultset('TmUser')
    ->search(
    { username => $current_username, 'role.name' => 'federation' },
    { prefetch => 'role' } )->single();

  return $tm_user;
}

sub add_federation {
  my $self  = shift;
  my $cname = shift;
  my $ttl   = shift;
  my $federation_id;

  my $federation = $self->db->resultset('Federation')->find_or_create(
    {   cname => $cname,
      ttl   => $ttl
    }
  );
  if ( defined $federation ) {
    $federation_id = $federation->id;
  }
  return $federation_id;
}

sub add_federation_deliveryservice {
  my $self          = shift;
  my $federation_id = shift;
  my $xml_id        = shift;

  my $fd
    = $self->db->resultset('FederationDeliveryservice')->find_or_create(
    {   federation      => $federation_id,
      deliveryservice => $self->db->resultset('Deliveryservice')
        ->search( { xml_id => $xml_id } )->get_column('id')->single()
    }
    );
  return $fd;
}

sub add_resolver {
  my $self          = shift;
  my $resolvers     = shift;
  my $federation_id = shift;
  my $type_name     = shift;
  my $resolver;

  foreach my $r ( @{$resolvers} ) {
    for my $ip ($r) {
      my $valid_ip = Net::CIDR::cidrvalidate($ip);
      if ( !defined $valid_ip ) {
        next;
      }

      $resolver
        = $self->db->resultset('FederationResolver')->find_or_create(
        {   ip_address => $ip,
          type       => $self->db->resultset('Type')
            ->search( { name => $type_name } )->get_column('id')
            ->single()
        }
        );

      if ( defined $resolver ) {
        $self->add_federation_federation_resolver( $federation_id,
          $resolver->id );
      }
    }
  }

  sub add_federation_federation_resolver {
    my $self          = shift;
    my $federation_id = shift;
    my $resolver_id   = shift;

    $self->db->resultset('FederationFederationResolver')->find_or_create(
      {   federation          => $federation_id,
        federation_resolver => $resolver_id
      }
    );
  }

}

1;
