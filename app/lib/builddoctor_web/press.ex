defmodule BuilddoctorWeb.Press do
  @moduledoc "The parts of a newspaper: typed text, flickering lines, press photos and the chart of seconds."
  use BuilddoctorWeb, :html

  alias BuilddoctorWeb.AuditView

  attr :id, :string, required: true
  attr :text, :string, required: true
  attr :live, :boolean, default: false
  attr :slow, :boolean, default: false

  @doc "Text that is written while somebody watches. The whole text is there from the start."
  def typed(assigns) do
    ~H"""
    <span
      id={@id}
      phx-hook="Typed"
      phx-update="ignore"
      data-live={to_string(@live)}
      data-pace={if @slow, do: "70", else: "32"}
    >{@text}</span>
    """
  end

  attr :widths, :list, default: [100, 96, 99, 88, 62]
  attr :head, :integer, default: nil

  @doc "Where text will stand, while the analysis runs."
  def lines(assigns) do
    ~H"""
    <div class="lines" aria-hidden="true">
      <i :if={@head} class="h" style={"width:#{@head}%"}></i>
      <i
        :for={{w, n} <- Enum.with_index(@widths)}
        style={"width:#{w}%;animation-delay:-#{rem(n * 37, 170) / 100}s"}
      ></i>
    </div>
    """
  end

  attr :audit, :map, required: true
  attr :place, :integer, required: true
  attr :picture, :map, default: nil
  attr :lines, :list, default: []
  attr :working, :boolean, default: false
  attr :live, :boolean, default: false
  attr :auto, :boolean, default: false

  def photo(%{picture: %{state: :done}} = assigns) do
    ~H"""
    <figure
      id={"photo-#{@audit.id}-#{@place}"}
      class="press-photo"
      phx-hook="Photo"
      phx-update="ignore"
      data-live={to_string(@live)}
      data-auto={to_string(@auto)}
    >
      <img
        src={photo_url(@picture, "jpg")}
        data-moving={photo_url(@picture, "webp")}
        alt={AuditView.line(@lines, :scene, @place) || alt(@picture)}
        width="768"
        height="512"
        loading={if @auto, do: "eager", else: "lazy"}
      />
      <button type="button" aria-label="Play the picture" hidden>Play</button>
      <figcaption>
        {AuditView.line(@lines, :caption, @place)} <span class="text-moss">AI illustration.</span>
      </figcaption>
    </figure>
    """
  end

  def photo(%{working: true, picture: picture} = assigns)
      when is_nil(picture) or picture.state != :failed do
    ~H"""
    <figure id={"dark-#{@place}"} class="press-photo">
      <div class="dark" data-busy={to_string(@picture != nil)}></div>
      <figcaption>
        {if @picture, do: "In the darkroom", else: "The photographer is on the way"}
      </figcaption>
    </figure>
    """
  end

  def photo(assigns), do: ~H""

  @doc "The address of a finished picture; a new picture has a new address."
  def photo_url(%{audit_id: id, place: place, updated_at: at}, kind),
    do: ~p"/a/#{id}/photo/#{"#{place}.#{kind}"}?#{[v: DateTime.to_unix(at)]}"

  defp who(%{figure: :keeper}), do: "A lighthouse keeper"

  defp who(%{figure: figure}) do
    if figure in [:architect, :astronomer, :engineer, :officer, :operator],
      do: "An #{figure}",
      else: "A #{figure}"
  end

  @doc "What a picture shows if the editor wrote no scene for it, from the closed lists of its request."
  def alt(%{scene: scene} = picture) do
    who = who(picture)
    low = String.downcase(who)

    case scene do
      :queue ->
        "A long line of people waits behind #{low}."

      :counter ->
        "People press their noses against a closed counter; #{low} drinks coffee behind it."

      :bench ->
        "People on a long bench look up at #{low}."

      :slow ->
        "#{who} works while travelers sleep on their suitcases."

      :marathon ->
        "#{who} works beside a finish line with exhausted runners."

      :snail ->
        "#{who} watches a snail on the workbench."

      :cost ->
        "#{who} watches coins roll away."

      :meter ->
        "A taxi waits while #{low} searches every pocket."

      :flaky ->
        "#{who} taps a lamp that switches on and off."

      :coin ->
        "#{who} flips a coin again and again."

      :upkeep ->
        "#{who} dusts an old cabinet."

      :cobweb ->
        "#{who} pulls a long cobweb off a machine."

      :newsroom ->
        "A calm newsroom at night."

      :shelves ->
        "A person looks into a box in a quiet archive."

      :telegraph ->
        "A person with headphones in a telegraph office."

      :council ->
        "Four editors sit around a table discussing papers."

      :empty ->
        "A reporter waits beside a printing press without paper."

      :portrait ->
        "#{who} at work."
    end
  end

  attr :grade, :map, required: true
  attr :big, :boolean, default: false

  @doc "The grade as a stamp; without one, a blank place."
  def grade(assigns) do
    ~H"""
    <span
      class={["stamp", @big && "big", @grade == nil && "blank"]}
      role="img"
      aria-label={if @grade, do: "Grade #{@grade.letter}", else: "No grade"}
    >{if @grade, do: @grade.letter, else: "–"}</span>
    """
  end

  attr :wait, :integer, required: true
  attr :work, :integer, required: true

  @doc "One mark per second."
  def seconds(assigns) do
    ~H"""
    <figure id="seconds" class="bg-sun p-4">
      <svg
        viewBox={"0 0 500 #{20 * ceil((@wait + @work) / 25)}"}
        class="block h-auto w-full"
        role="img"
        aria-label={"#{@wait} round marks for seconds of waiting, #{@work} squares for seconds of work"}
      >
        <path d={circles(@wait)} fill="#b8200f" /><path d={squares(@wait, @work)} fill="#17130f" />
      </svg>
      <figcaption class="mt-3 font-bold">
        <span class="mr-4">● {@wait} s waiting</span><span class="mr-4">■ {@work} s working</span>One mark is one second.
      </figcaption>
    </figure>
    """
  end

  defp circles(n) do
    for i <- 0..(n - 1)//1, into: "" do
      "M#{rem(i, 25) * 20 + 2.5} #{div(i, 25) * 20 + 10}a7.5 7.5 0 1 0 15 0a7.5 7.5 0 1 0-15 0"
    end
  end

  defp squares(from, n) do
    for i <- from..(from + n - 1)//1, into: "" do
      "M#{rem(i, 25) * 20 + 2} #{div(i, 25) * 20 + 2}h16v16h-16z"
    end
  end

  attr :finding, :map, required: true

  @doc "The fact-checker's word about the first story, small."
  def stamp(assigns) do
    ~H"""
    <span class={["inline-block px-2 font-bold whitespace-nowrap", AuditView.stamp_class(@finding)]}>
      Jev: {AuditView.stamp(@finding)}, {AuditView.percent(@finding.support_probability)}
    </span>
    """
  end
end
