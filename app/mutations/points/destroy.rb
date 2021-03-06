module Points
  class Destroy < Mutations::Command
    STILL_IN_USE  = "Could not delete the following item(s): %s. Item(s) are "\
                    "in use by the following sequence(s): %s."

    required do
      model :device, class: Device
      array :point_ids, class: Integer
    end

    optional { boolean :hard_delete, default: false }

    P = :point
    S = :sequence

    def validate
      # Collect names of sequences that still use this point.
      errors = (tool_seq + point_seq)
        .group_by(&:sequence_name)
        .to_a
        .reduce({S => [], P => []}) do |total, (seq_name, data)|
          total[S].push(seq_name)
          total[P].push(*(data || []).map(&:fancy_name))
          total
        end

      points = errors[P].sort.uniq.join(", ")

      if points.present?
        sequences = errors[S].sort.uniq.join(", ")
        errors    = STILL_IN_USE % [points, sequences]

        add_error :whoops, :in_use, errors
      end
    end

    def execute
      if hard_delete
        points.destroy_all
      else
        Point.transaction do
          archive_points
          destroy_all_others
        end
      end
    end

  private

    def archive_points
      points
        .where(pointer_type: "GenericPointer")
        .update_all(discarded_at: Time.now)
    end

    def destroy_all_others
      points
      .where
      .not(pointer_type: "GenericPointer")
      .destroy_all
    end

    def points
      @points ||= Point.where(id: point_ids)
    end

    def every_tool_id_as_json
      points
        .where.not(tool_id: nil)
        .pluck(:tool_id)
        .uniq
        .map(&:to_json)
        .map(&:to_i)
    end

    def point_seq
      @point_seq ||= InUsePoint
        .where(point_id: points.pluck(:id))
        .to_a
    end

    def tool_seq
      @tool_seq ||= InUseTool
        .where(tool_id: every_tool_id_as_json, device_id: device.id)
        .to_a
    end
  end
end
