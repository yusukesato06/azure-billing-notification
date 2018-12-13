class CaluculateCost
  def initialize(usages, meters)
    @usages = usages
    @meters = meters
  end

  def correlate_usage_to_rate
    @usages.each do |u|
      @meters.each do |j|
        ### usagesとrateをMeterIDで紐付け
        next unless j['MeterId'] == u.meter_id
        u.meter_name = j['MeterName']
        u.meter_category = j['MeterCategory']
        u.meter_sub_category = j['MeterSubCategory']
        u.meter_region = j['MeterRegion']
        u.rate = j['MeterRates']['0']
        u.included_quantity = j['IncludedQuantity']
      end
    end
  end

  def calc_total_cost
    LOG_OUT.info "Calculation total cost."
    total_cost = 0
    @usages.each do |u|
      unless u.rate == nil
        total_cost += u.quantity * u.rate
      end
    end
    LOG_OUT.info "Done."
    return total_cost
  end

  def calc_rg_total_cost
    LOG_OUT.info "Calculation grouping total cost"
    total_rg_cost = {}
    @usages.each do |u|
      unless u.rate == nil
        cost = u.quantity * u.rate
        if !total_rg_cost[u.resource_group_name]
          total_rg_cost[u.resource_group_name] = cost
        else
          total_rg_cost[u.resource_group_name] += cost
        end
      end
    end
    ### コストの高い順にソート
    total_rg_cost = Hash[ total_rg_cost.sort_by{ |_, v| -v } ]
    LOG_OUT.info "Done."
    return total_rg_cost
  end
end