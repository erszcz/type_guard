defmodule TypeGuard.PolymorphicEmbedTest do
  use ExUnit.Case, async: true

  alias TypeGuard.Fixtures.{Address, Image, Post, Video}

  test "the integration is active" do
    assert TypeGuard.PolymorphicEmbed.available?()
  end

  test "a cast post is valid" do
    changeset =
      Post.changeset(%{
        "title" => "Hello",
        "cover" => %{"kind" => "image", "url" => "/a.png", "width" => 10},
        "attachments" => [%{"kind" => "video", "url" => "/b.mp4", "seconds" => 3}]
      })

    assert changeset.valid?
    assert TypeGuard.valid?(Ecto.Changeset.apply_changes(changeset))
    assert TypeGuard.Ecto.validate(changeset).valid?
  end

  test "an embed field accepts only its declared modules, with valid fields" do
    image = %Image{url: "/a.png", width: 10}

    assert [] == TypeGuard.invalid_fields(%Post{title: "t", cover: nil, attachments: [image]})
    assert [:cover] == TypeGuard.invalid_fields(%Post{title: "t", cover: :none, attachments: []})

    for attachment <- [
          %{url: "/a.png", width: 10},
          %Address{street: "s"},
          %Video{url: "/b", seconds: -1}
        ] do
      assert [:attachments] ==
               TypeGuard.invalid_fields(%Post{title: "t", attachments: [attachment]})
    end
  end
end
