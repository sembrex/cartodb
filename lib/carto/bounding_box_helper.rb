# encoding: utf-8
require_relative '../../lib/carto/table_utils'

module Carto::BoundingBoxHelper
  extend Carto::TableUtils

  DEFAULT_BOUNDS = {
    minlon: -179,
    maxlon: 179,
    minlat: -85.0511,
    maxlat: 85.0511
  }.freeze

  LIMIT_BOUNDS = {
    minlon: -180,
    maxlon: 180,
    minlat: -90,
    maxlat: 90
  }.freeze

  def self.calculate_bounding_box(db, table_name)
    get_table_bounds(db, table_name)
  rescue Sequel::DatabaseError => exception
    CartoDB::Logger.error(exception: exception, table: table_name)
    raise BoundingBoxError.new("Can't calculate the bounding box for table #{table_name}. ERROR: #{exception}")
  end

  def self.get_table_bounds(db, table_name)
    # (lon,lat) as comes out from postgis
    result = current_bbox_using_stats(db, table_name)
    {
      maxx: bound_for(result[:max][0].to_f, :minlon, :maxlon),
      maxy: bound_for(result[:max][1].to_f, :minlat, :maxlat),
      minx: bound_for(result[:min][0].to_f, :minlon, :maxlon),
      miny: bound_for(result[:min][1].to_f, :minlat, :maxlat)
    }
  end

  # Postgis stats-based calculation of bounds. Much faster but not always present, so needs a fallback
  def self.current_bbox_using_stats(db, table_name)
    # Less ugly (for tests at least) than letting an exception generate not having any table name
    return default_bbox unless table_name.present?

    # (lon,lat) as comes from postgis
    JSON.parse(db.execute(%{
      SELECT _postgis_stats ('#{table_name}', 'the_geom');
    }).first['_postgis_stats'])['extent'].symbolize_keys
  rescue => e
    if e.message =~ /stats for (.*) do not exist/i
      begin
        current_bbox(db, table_name)
      rescue
        default_bbox
      end
    else
      default_bbox
    end
  end

  def self.current_bbox(db, table_name)
    # (lon, lat) as comes from postgis (ST_X = Longitude, ST_Y = Latitude)
    # map has no geometries
    result = get_bbox_values(db, table_name, "the_geom")
    if result.all? { |_, value| value.nil? }
      default_bbox
    else
      # still (lon,lat) to be consistent with current_bbox_using_stats()
      {
        max: [result['maxx'].to_f, result['maxy'].to_f],
        min: [result['minx'].to_f, result['miny'].to_f]
      }
    end
  rescue Sequel::DatabaseError => exception
    CartoDB::Logger.error(exception: exception, table: table_name)
    raise BoundingBoxError.new("Can't calculate the bounding box for table #{table_name}. ERROR: #{exception}")
  end

  def self.bound_for(value, minimum, maximum)
    [[value, DEFAULT_BOUNDS.fetch(minimum)].max, DEFAULT_BOUNDS.fetch(maximum)].min
  end

  def self.default_bbox
    # (lon, lat) to be consistent with postgis queries
    {
      max: [DEFAULT_BOUNDS[:maxlon], DEFAULT_BOUNDS[:maxlat]],
      min: [DEFAULT_BOUNDS[:minlon], DEFAULT_BOUNDS[:minlat]]
    }
  end

  def self.get_bbox_values(db, table_name, column_name)
    result = db.execute(%{
      SELECT
        ST_XMin(ST_Extent(#{column_name})) AS minx,
        ST_YMin(ST_Extent(#{column_name})) AS miny,
        ST_XMax(ST_Extent(#{column_name})) AS maxx,
        ST_YMax(ST_Extent(#{column_name})) AS maxy
      FROM #{safe_table_name_quoting(table_name)} AS subq
    }).first

    result
  end

  def self.parse_bbox_parameters(bounding_box)
    bbox_coords = bounding_box.split(',').map { |coord| Float(coord) rescue nil }.compact
    if bbox_coords.length != 4
      raise CartoDB::BoundingBoxError.new('bounding box must have 4 coordinates: minx, miny, maxx, maxy')
    end
    { minx: bbox_coords[0], miny: bbox_coords[1], maxx: bbox_coords[2], maxy: bbox_coords[3] }
  end
end
