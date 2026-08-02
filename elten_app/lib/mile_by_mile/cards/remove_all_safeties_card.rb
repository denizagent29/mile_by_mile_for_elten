# frozen_string_literal: true

module MileByMile
  # Опциональная карточка «Снять все защиты». Играется на соперника.
  class RemoveAllSafetiesCard < Card
    def initialize
      super('Снять все защиты')
    end

    def opponent_only?
      true
    end
  end
end
