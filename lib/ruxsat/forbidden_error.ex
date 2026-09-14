defmodule Ruxsat.ForbiddenError do
  @moduledoc """
  Raised by `authorize!/3` when the action is not allowed.

  The message contains the action and the resource type only, never the
  subject, so it is safe to log.
  """

  defexception [:action, :resource]

  @impl true
  def message(%{action: action, resource: resource}) do
    "forbidden: #{inspect(action)} on #{inspect(resource)}"
  end
end
