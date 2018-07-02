CloudFormation do

  az_conditions_resources('SubnetPublic', maximum_availability_zones)

  EC2_SecurityGroup('SecurityGroupLoadBalancer') do
    GroupDescription FnJoin(' ', [ Ref('EnvironmentName'), component_name ])
    VpcId Ref('VPCId')
    SecurityGroupIngress sg_create_rules(securityGroups['loadbalancer'], ip_blocks)
  end

  atributes = []

  loadbalancer_attributes.each do |key,value|
    atributes << { Key: key, Value: value }
  end if loadbalancer_attributes.any?

  tags = []
  tags << { Key: "Environment", Value: Ref("EnvironmentName") }
  tags << { Key: "EnvironmentType", Value: Ref("EnvironmentType") }

  loadbalancer_tags.each do |key,value|
    tags << { Key: key, Value: value }
  end if loadbalancer_tags.any?

  ElasticLoadBalancingV2_LoadBalancer('LoadBalancer') do

    if loadbalancer_scheme == 'internal'
      Subnets az_conditional_resources('SubnetCompute', maximum_availability_zones)
      Scheme 'internal'
    else
      Subnets az_conditional_resources('SubnetPublic', maximum_availability_zones)
    end

    if loadbalancer_type == 'network'
      Type loadbalancer_type
    else
      SecurityGroups [ Ref('SecurityGroupLoadBalancer') ]
    end

    Tags tags if tags.any?
    LoadBalancerAttributes atributes if atributes.any?
  end

  targetgroups.each do |tg_name, tg|

    atributes = []

    tg['atributes'].each do |key,value|
      atributes << { Key: key, Value: value }
    end if tg.has_key?('atributes')

    tags = []
    tags << { Key: "Environment", Value: Ref("EnvironmentName") }
    tags << { Key: "EnvironmentType", Value: Ref("EnvironmentType") }

    tg['tags'].each do |key,value|
      tags << { Key: key, Value: value }
    end if tg.has_key?('tags')

    ElasticLoadBalancingV2_TargetGroup("#{tg_name}TargetGroup") do
      ## Required
      Port tg['port']
      Protocol tg['protocol'].upcase
      VpcId Ref('VPCId')
      ## Optional
      if tg.has_key?('healthcheck')
        HealthCheckPort tg['healthcheck']['port'] if tg['healthcheck'].has_key?('port')
        HealthCheckProtocol tg['healthcheck']['protocol'] if tg['healthcheck'].has_key?('port')
        HealthCheckIntervalSeconds tg['healthcheck']['interval'] if tg['healthcheck'].has_key?('interval')
        HealthCheckTimeoutSeconds tg['healthcheck']['timeout'] if tg['healthcheck'].has_key?('timeout')
        HealthyThresholdCount tg['healthcheck']['heathy_count'] if tg['healthcheck'].has_key?('heathy_count')
        UnhealthyThresholdCount tg['healthcheck']['unheathy_count'] if tg['healthcheck'].has_key?('unheathy_count')
        HealthCheckPath tg['healthcheck']['path'] if tg['healthcheck'].has_key?('path')
        Matcher ({ HttpCode: tg['healthcheck']['code'] }) if tg['healthcheck'].has_key?('code')
      end

      TargetType tg['type'] if tg.has_key?('type')
      TargetGroupAttributes atributes if atributes.any?

      Tags tags if tags.any?
    end

    Output("#{tg_name}TargetGroup", Ref("#{tg_name}TargetGroup"))

    if tg.has_key?('rules')
      listener_conditions = []
      tg['rules'].each do |rule|
        if rule.key?("path")
          listener_conditions << { Field: "path-pattern", Values: [ condition["path"] ] }
        end
        if rule.key?("host")
          hosts = []
          if rule["host"].include?('.')
            hosts << condition["host"]
          else
            hosts << FnJoin("", [ rule["host"], ".", Ref("EnvironmentName"), ".", Ref('DnsDomain') ])
          end
          listener_conditions << { Field: "host-header", Values: hosts }
        end

        ElasticLoadBalancingV2_ListenerRule("#{tg_name}Rule") do
          Actions [{ Type: "forward", TargetGroupArn: Ref("#{tg_name}TargetGroup") }]
          Conditions listener_conditions
          ListenerArn Ref("#{tg['listener']}Listener")
          Priority tg['priority'].to_i
        end
        
      end
    end

  end if defined?('targetgroups')

  listeners.each do |listener_name, listener|
    ElasticLoadBalancingV2_Listener("#{listener_name}Listener") do
      Protocol listener['protocol'].upcase
      Certificates [{CertificateArn: Ref('SslCertId')}] if listener['protocol'] == 'https'
      Port listener['port']
      DefaultActions ([
        TargetGroupArn: Ref("#{listener['default_targetgroup']}TargetGroup"),
        Type: "forward"
      ])
      LoadBalancerArn Ref('LoadBalancer')
    end
    Output("#{listener_name}Listener") { Value(Ref("#{listener_name}Listener")) }
  end if defined?('listeners')

  if defined? records
    records.each do |record|
      Route53_RecordSet("#{record.gsub('*','Wildcard')}LoadBalancerRecord") do
        HostedZoneName FnJoin("", [ Ref("EnvironmentName"), ".", Ref('DnsDomain'), "." ])
        Name FnJoin("", [ "#{record}.", Ref("EnvironmentName"), ".", Ref('DnsDomain'), "." ])
        Type 'A'
        AliasTarget ({
          DNSName: FnGetAtt("LoadBalancer","DNSName"),
          HostedZoneId: FnGetAtt("LoadBalancer","CanonicalHostedZoneID")
        })
      end
    end
  end

  Output('LoadBalancer', Ref('LoadBalancer'))
  Output('SecurityGroupLoadBalancer', Ref('SecurityGroupLoadBalancer'))

end
