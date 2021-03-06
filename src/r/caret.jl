# Wrapper to CARET library.
module CaretWrapper

importall Combine.Types
importall Combine.Util

using PyCall
@pyimport rpy2.robjects as RO
@pyimport rpy2.robjects.packages as RP
@pyimport rpy2.robjects.numpy2ri as N2R
N2R.activate()
RP.importr("caret")

export CRTLearner,
       fit!,
       transform!

# Convert vector to R equivalent.
vector_to_r{T<:Int}(vector::Vector{T}) = RO.IntVector(vector)
vector_to_r{T<:Real}(vector::Vector{T}) = RO.FloatVector(vector)
vector_to_r{T<:Bool}(vector::Vector{T}) = RO.BoolVector(vector)
vector_to_r{T<:AbstractString}(vector::Vector{T}) = RO.StrVector(vector)
function vector_to_r(vector::Vector{Any})
  vec_eltype = infer_eltype(vector)
  if vec_eltype == Any
    error("Cannot handle R conversion for vector with differing element types.")
  end

  return vector_to_r(convert(Vector{vec_eltype}, vector))
end
vector_to_r(vector::Vector) = error(
  "Cannot handle R conversion for $(typeof(vector))."
)


# Builds R dataframe out of dataset.
# Returns (dataframe, label_factor_levels).
function dataset_to_r_dataframe(
  instances::Matrix, labels=nothing)

  # Build dataframe
  df_dict = Dict()
  for col in 1:size(instances, 2)
    df_dict["X$col"] = vector_to_r(instances[:, col])
  end

  if labels != nothing
    r_labels = RO.FactorVector(labels)
    df_dict["Y"] = r_labels
    return (RO.DataFrame(df_dict), r_labels[:levels])
  else
    return (RO.DataFrame(df_dict), nothing) 
  end
end


# CARET wrapper that provides access to all learners.
# 
# Options for the specific CARET learner is to be passed
# in `options[:impl_options]` dictionary.
type CRTLearner <: Learner
  model
  options
  
  function CRTLearner(options=Dict())
    default_options = Dict(
      # Output to train against
      # (:class).
      :output => :class,
      :learner => "svmLinear",
      :impl_options => Dict()
    )
    new(nothing, nested_dict_merge(default_options, options)) 
  end
end

function fit!(crtw::CRTLearner, instances::Matrix, labels::Vector)
  impl_options = crtw.options[:impl_options]
  crtw.model = Dict()
  crtw.model[:learner] = crtw.options[:learner]

  # Build R dataframe out of dataset
  (r_dataset_df, label_factors) = dataset_to_r_dataframe(instances, labels)

  # Assign label factors
  crtw.model[:label_factors] = collect(label_factors)

  # Train model
  caret_formula = RO.Formula("Y ~ .")
  r_fit_control = pycall(RO.r[:trainControl], PyObject,
    method = "none"
  )
  if isempty(impl_options)
    r_model = pycall(RO.r[:train], PyObject,
      caret_formula,
      method = crtw.model[:learner],
      data = r_dataset_df,
      trControl = r_fit_control,
      tuneLength = 1
    )
  else
    r_model = pycall(RO.r[:train], PyObject,
      caret_formula,
      method = crtw.model[:learner],
      data = r_dataset_df,
      trControl = r_fit_control,
      tuneGrid = RO.DataFrame(impl_options)
    )
  end
  crtw.model[:r_model] = r_model
end

function transform!(crtw::CRTLearner, instances::Matrix)
  (r_instance_df, _) = dataset_to_r_dataframe(instances)
  predictions = collect(pycall(RO.r[:predict], PyObject,
    crtw.model[:r_model],
    newdata = r_instance_df
  ))
  label_factors = crtw.model[:label_factors]
  predictions = map(x -> label_factors[x], predictions)
  return predictions
end

end # module
