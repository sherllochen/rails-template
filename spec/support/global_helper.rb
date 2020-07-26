module Global
  # parse response.body to json
  module Utils
    def expect_equal_with_params(obj, hash, params=nil)
      result = true
      params ||= hash.keys
      hash.each do |k, v|
        if params.include?(k) && obj.attributes[k] != v
          reslut =false
          break
        end
      end
      return result
    end

    def hash_compare(h1, h2, params=nil)
      if params
        params = params.map { |item| item.to_sym }
      else
        params = h1.keys
      end
      result = true
      params.each do |k|
        if h1[k]||h1[k.to_s] != h2[k] || h2[k.to_s]
          result = false
          break
        end
      end
      return result
    end
  end
end