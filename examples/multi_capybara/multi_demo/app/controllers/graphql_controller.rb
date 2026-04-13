class GraphqlController < ActionController::API
  def execute
    result = DemoSchema.execute(
      params[:query].to_s,
      variables: ensure_hash(params[:variables]),
      context: {},
      operation_name: params[:operationName]
    )
    render json: result
  end

  private

  def ensure_hash(ambiguous_param)
    case ambiguous_param
    when String
      if ambiguous_param.present?
        ensure_hash(JSON.parse(ambiguous_param))
      else
        {}
      end
    when Hash, ActionController::Parameters
      ambiguous_param.to_unsafe_h
    when nil
      {}
    else
      raise ArgumentError, "Unexpected parameter: #{ambiguous_param}"
    end
  end
end
